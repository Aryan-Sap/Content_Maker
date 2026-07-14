import 'dart:convert';
import 'dart:io';

/// Which editing pipeline a project was created with.
enum ProjectPipeline { simple, custom }

extension ProjectPipelineDetails on ProjectPipeline {
  String get label {
    return switch (this) {
      ProjectPipeline.simple => 'Simple — Auto Render',
      ProjectPipeline.custom => 'Custom — Timeline Editor',
    };
  }
}

class UserProfile {
  const UserProfile({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory UserProfile.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return UserProfile(
      id: '${map['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      name: '${map['name'] ?? 'Creator'}',
    );
  }
}

class ProjectSummary {
  const ProjectSummary({
    required this.id,
    required this.name,
    required this.pipeline,
    required this.ownerId,
    required this.createdAt,
    required this.lastOpenedAt,
  });

  final String id;
  final String name;
  final ProjectPipeline pipeline;
  final String ownerId;
  final DateTime createdAt;
  final DateTime lastOpenedAt;

  ProjectSummary copyWith({DateTime? lastOpenedAt}) {
    return ProjectSummary(
      id: id,
      name: name,
      pipeline: pipeline,
      ownerId: ownerId,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'pipeline': pipeline.name,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
  };

  factory ProjectSummary.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return ProjectSummary(
      id: '${map['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      name: '${map['name'] ?? 'Untitled project'}',
      pipeline: ProjectPipeline.values.firstWhere(
        (value) => value.name == map['pipeline'],
        orElse: () => ProjectPipeline.simple,
      ),
      ownerId: '${map['ownerId'] ?? ''}',
      createdAt:
          DateTime.tryParse('${map['createdAt']}') ?? DateTime.now(),
      lastOpenedAt:
          DateTime.tryParse('${map['lastOpenedAt']}') ?? DateTime.now(),
    );
  }
}

/// Persists local user profiles and the project library as a single JSON
/// document under the per-user app data folder.
class AppSessionStore {
  const AppSessionStore({this.storePath});

  final String? storePath;

  Future<({List<UserProfile> profiles, List<ProjectSummary> projects})>
  load() async {
    final file = _storeFile();
    if (!file.existsSync()) {
      return (profiles: <UserProfile>[], projects: <ProjectSummary>[]);
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return (profiles: <UserProfile>[], projects: <ProjectSummary>[]);
      }
      final profiles = decoded['profiles'];
      final projects = decoded['projects'];
      return (
        profiles: profiles is List
            ? profiles.map(UserProfile.fromJson).toList()
            : <UserProfile>[],
        projects: projects is List
            ? projects.map(ProjectSummary.fromJson).toList()
            : <ProjectSummary>[],
      );
    } on FormatException {
      return (profiles: <UserProfile>[], projects: <ProjectSummary>[]);
    }
  }

  Future<void> save({
    required List<UserProfile> profiles,
    required List<ProjectSummary> projects,
  }) async {
    final file = _storeFile();
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert({
        'schemaVersion': 1,
        'profiles': [for (final profile in profiles) profile.toJson()],
        'projects': [for (final project in projects) project.toJson()],
      })}\n',
    );
  }

  File _storeFile() {
    final explicitPath = storePath;
    if (explicitPath != null) {
      return File(explicitPath);
    }
    final basePath =
        Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return File(
      '$basePath${Platform.pathSeparator}Content Maker'
      '${Platform.pathSeparator}session.json',
    );
  }
}
