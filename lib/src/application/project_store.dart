import 'dart:convert';
import 'dart:io';

import '../domain/editing/manual_edit_project.dart';

class ProjectStore {
  const ProjectStore();

  Future<ManualEditProject> open(String path) async {
    final file = File(path);
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Project file must contain a JSON object.');
    }
    return ManualEditProject.fromJson(decoded);
  }

  Future<void> save(ManualEditProject project, String path) async {
    final normalizedPath = path.toLowerCase().endsWith('.cmproj')
        ? path
        : '$path.cmproj';
    final file = File(normalizedPath);
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(project.toJson())}\n');
  }
}
