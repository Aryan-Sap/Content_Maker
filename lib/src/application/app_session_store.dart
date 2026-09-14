import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
    this.projectFilePath,
  });

  final String id;
  final String name;
  final ProjectPipeline pipeline;
  final String ownerId;
  final DateTime createdAt;
  final DateTime lastOpenedAt;
  final String? projectFilePath;

  ProjectSummary copyWith({DateTime? lastOpenedAt, String? projectFilePath}) {
    return ProjectSummary(
      id: id,
      name: name,
      pipeline: pipeline,
      ownerId: ownerId,
      createdAt: createdAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      projectFilePath: projectFilePath ?? this.projectFilePath,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'pipeline': pipeline.name,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'lastOpenedAt': lastOpenedAt.toIso8601String(),
    'projectFilePath': projectFilePath,
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
      createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.now(),
      lastOpenedAt:
          DateTime.tryParse('${map['lastOpenedAt']}') ?? DateTime.now(),
      projectFilePath: map['projectFilePath'] is String
          ? map['projectFilePath'] as String
          : null,
    );
  }
}

/// Persists local user profiles and the project library as a single JSON
/// document under the per-user app data folder.
class AppSessionStore {
  const AppSessionStore({this.storePath});

  final String? storePath;

  /// Whether the first-run product walkthrough has been completed.
  Future<bool> hasCompletedTutorial() async {
    final decoded = await _readDocument();
    return decoded['tutorialCompleted'] == true;
  }

  /// Marks the walkthrough complete without disturbing profiles or projects.
  Future<void> markTutorialCompleted() async {
    final file = await _storeFile();
    final decoded = await _readDocument();
    decoded['schemaVersion'] = 2;
    decoded['tutorialCompleted'] = true;
    await _writeDocument(file, decoded);
  }

  Future<({List<UserProfile> profiles, List<ProjectSummary> projects})>
  load() async {
    try {
      final decoded = await _readDocument();
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
    final file = await _storeFile();
    final decoded = await _readDocument();
    await _writeDocument(file, {
      'schemaVersion': 2,
      'tutorialCompleted': decoded['tutorialCompleted'] == true,
      'profiles': [for (final profile in profiles) profile.toJson()],
      'projects': [for (final project in projects) project.toJson()],
    });
  }

  Future<Map<String, Object?>> _readDocument() async {
    final file = await _storeFile();
    if (!file.existsSync()) {
      return <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
    } on FormatException {
      // A damaged session behaves like a fresh install and is replaced on save.
    }
    return <String, Object?>{};
  }

  Future<void> _writeDocument(File file, Map<String, Object?> document) async {
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(document)}\n');
  }

  Future<File> _storeFile() async {
    final explicitPath = storePath;
    if (explicitPath != null) {
      return File(explicitPath);
    }
    final basePath = Platform.isAndroid || Platform.isIOS
        ? (await getApplicationSupportDirectory()).path
        : Platform.environment['APPDATA'] ??
              Platform.environment['HOME'] ??
              Directory.current.path;
    return File(
      '$basePath${Platform.pathSeparator}Content Maker'
      '${Platform.pathSeparator}session.json',
    );
  }
}
