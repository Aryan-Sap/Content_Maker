import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/application/auto_edit_preset_store.dart';
import 'package:content_maker/src/domain/rendering/auto_edit_preset.dart';
import 'package:content_maker/src/domain/rendering/export_settings.dart';
import 'package:content_maker/src/domain/rendering/render_preset.dart';

void main() {
  test('auto edit preset json round-trips render edits', () {
    final preset = AutoEditPreset(
      id: 'preset-a',
      name: 'Vibrant Shorts',
      renderPreset: RenderPreset.gameplayShort.copyWith(
        exportSettings: RenderPreset.gameplayShort.exportSettings.copyWith(
          motionBlur: true,
          temporalSmoothing: TemporalSmoothingMode.motionInterpolation,
          panningBlurIntensity: 0.4,
        ),
      ),
      trimStartSeconds: 1.5,
      trimEndSeconds: 8.5,
      sourceAudioVolume: 0.7,
      overlayAudioVolume: 1.1,
    );

    final restored = AutoEditPreset.fromJson(preset.toJson());

    expect(restored.toJson(), preset.toJson());
    expect(restored.renderPreset.exportSettings.motionBlur, isTrue);
    expect(
      restored.renderPreset.exportSettings.temporalSmoothing,
      TemporalSmoothingMode.motionInterpolation,
    );
  });

  test('auto edit preset store saves and loads presets', () async {
    final directory = await Directory.systemTemp.createTemp(
      'content_maker_auto_presets_test_',
    );
    addTearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    final path = '${directory.path}${Platform.pathSeparator}presets.json';
    final store = AutoEditPresetStore(storePath: path);
    final presets = [
      const AutoEditPreset(
        id: 'preset-a',
        name: 'Clean',
        renderPreset: RenderPreset.gameplayShort,
      ),
    ];

    await store.saveAll(presets);
    final restored = await store.load();

    expect(restored.single.toJson(), presets.single.toJson());
  });
}
