import 'dart:convert';
import 'dart:io';

import '../domain/rendering/auto_edit_preset.dart';

class AutoEditPresetStore {
  const AutoEditPresetStore({this.storePath});

  final String? storePath;

  Future<List<AutoEditPreset>> load() async {
    final file = _storeFile();
    if (!file.existsSync()) {
      return const [];
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Preset store must contain a JSON object.');
    }
    final presets = decoded['presets'];
    if (presets is! List) {
      return const [];
    }
    return presets.map(AutoEditPreset.fromJson).toList(growable: false);
  }

  Future<void> saveAll(List<AutoEditPreset> presets) async {
    final file = _storeFile();
    final parent = file.parent;
    if (!parent.existsSync()) {
      await parent.create(recursive: true);
    }
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      '${encoder.convert({
        'schemaVersion': 1,
        'presets': [for (final preset in presets) preset.toJson()],
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
      '${Platform.pathSeparator}auto_edit_presets.json',
    );
  }
}
