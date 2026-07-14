import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../application/app_session_store.dart';
import '../application/auto_edit_preset_store.dart';
import '../application/create_shorts_export.dart';
import '../domain/rendering/auto_edit_preset.dart';
import '../domain/rendering/composition_spec.dart';
import '../domain/rendering/export_settings.dart';
import '../domain/rendering/render_job.dart';
import '../domain/rendering/render_preset.dart';
import '../domain/rendering/video_asset.dart';
import '../infrastructure/ffmpeg/ffmpeg_video_processor.dart';
import '../infrastructure/notifications/desktop_notifier.dart';
import 'manual_editor_screen.dart';
import 'publishing/accounts_dialog.dart';
import 'publishing/publish_panel.dart';
import 'widgets/rendered_clip_player.dart';

enum _WorkspaceMode { automatic, manual }

enum _OutputResolution { vertical, square, landscape }

enum _ColorStyle { natural, enhanced, vibrant, dark, cinematic }

extension _WorkspaceModeDetails on _WorkspaceMode {
  String get label {
    return switch (this) {
      _WorkspaceMode.automatic => 'Auto Render',
      _WorkspaceMode.manual => 'Custom Editor',
    };
  }

  IconData get icon {
    return switch (this) {
      _WorkspaceMode.automatic => Icons.auto_awesome_outlined,
      _WorkspaceMode.manual => Icons.timeline_outlined,
    };
  }
}

extension _OutputResolutionDetails on _OutputResolution {
  String get label {
    return switch (this) {
      _OutputResolution.vertical => 'Short',
      _OutputResolution.square => 'Square',
      _OutputResolution.landscape => 'Wide',
    };
  }

  IconData get icon {
    return switch (this) {
      _OutputResolution.vertical => Icons.crop_portrait_outlined,
      _OutputResolution.square => Icons.crop_square_outlined,
      _OutputResolution.landscape => Icons.crop_16_9_outlined,
    };
  }

  int get width {
    return switch (this) {
      _OutputResolution.vertical => 1080,
      _OutputResolution.square => 1080,
      _OutputResolution.landscape => 1920,
    };
  }

  int get height {
    return switch (this) {
      _OutputResolution.vertical => 1920,
      _OutputResolution.square => 1080,
      _OutputResolution.landscape => 1080,
    };
  }
}

extension _ColorStyleDetails on _ColorStyle {
  String get label {
    return switch (this) {
      _ColorStyle.natural => 'Natural',
      _ColorStyle.enhanced => 'Enhanced',
      _ColorStyle.vibrant => 'Vibrant',
      _ColorStyle.dark => 'Dark',
      _ColorStyle.cinematic => 'Cinematic',
    };
  }

  IconData get icon {
    return switch (this) {
      _ColorStyle.natural => Icons.tonality_outlined,
      _ColorStyle.enhanced => Icons.auto_awesome_outlined,
      _ColorStyle.vibrant => Icons.palette_outlined,
      _ColorStyle.dark => Icons.dark_mode_outlined,
      _ColorStyle.cinematic => Icons.movie_filter_outlined,
    };
  }

  ({
    double backgroundDarkness,
    double backgroundSaturation,
    double foregroundSaturation,
    double contrast,
    double gamma,
  })
  get values {
    return switch (this) {
      _ColorStyle.natural => (
        backgroundDarkness: 0,
        backgroundSaturation: 1,
        foregroundSaturation: 1,
        contrast: 1,
        gamma: 1,
      ),
      _ColorStyle.enhanced => (
        backgroundDarkness: 0.06,
        backgroundSaturation: 1.12,
        foregroundSaturation: 1.22,
        contrast: 1.12,
        gamma: 1.02,
      ),
      _ColorStyle.vibrant => (
        backgroundDarkness: 0.04,
        backgroundSaturation: 1.24,
        foregroundSaturation: 1.38,
        contrast: 1.18,
        gamma: 1.03,
      ),
      _ColorStyle.dark => (
        backgroundDarkness: 0.16,
        backgroundSaturation: 1.06,
        foregroundSaturation: 1.12,
        contrast: 1.2,
        gamma: 0.96,
      ),
      _ColorStyle.cinematic => (
        backgroundDarkness: 0.1,
        backgroundSaturation: 0.92,
        foregroundSaturation: 1.08,
        contrast: 1.16,
        gamma: 0.98,
      ),
    };
  }
}

class RenderHomeScreen extends StatefulWidget {
  const RenderHomeScreen({
    super.key,
    this.projectName,
    this.initialPipeline = ProjectPipeline.simple,
  });

  /// Shown in the app bar when opened from the project hub.
  final String? projectName;

  /// Chooses the workspace the project opens into (the switcher stays
  /// available so users can move between pipelines at any time).
  final ProjectPipeline initialPipeline;

  @override
  State<RenderHomeScreen> createState() => _RenderHomeScreenState();
}

class _RenderHomeScreenState extends State<RenderHomeScreen> {
  static const _filePickerChannel = MethodChannel('content_maker/file_picker');

  final _sourceController = TextEditingController();
  final _outputController = TextEditingController();
  final _audioController = TextEditingController();
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController();
  final _exportUseCase = const CreateShortsExport(FfmpegVideoProcessor());
  final _presetStore = const AutoEditPresetStore();

  StreamSubscription<RenderProgress>? _renderSubscription;
  _WorkspaceMode _workspaceMode = _WorkspaceMode.automatic;
  RenderPreset _preset = RenderPreset.gameplayShort;
  _OutputResolution _resolution = _OutputResolution.vertical;
  _ColorStyle _colorStyle = _ColorStyle.vibrant;
  final List<String> _sourceQueue = [];
  List<AutoEditPreset> _savedEditPresets = const [];
  AutoEditPreset? _copiedEditPreset;
  String? _autoSuggestedOutputPath;
  String? _lastRenderedOutput;
  double? _progress;
  String _status = 'Ready';
  bool _isRendering = false;
  double _sourceAudioVolume = 1;
  double _overlayAudioVolume = 0.75;

  bool get _canRender =>
      !_isRendering &&
      _renderSourcePaths.isNotEmpty &&
      (_renderSourcePaths.length > 1 ||
          _outputController.text.trim().isNotEmpty);

  List<String> get _renderSourcePaths {
    if (_sourceQueue.isNotEmpty) {
      return List.unmodifiable(_sourceQueue);
    }
    final sourcePath = _cleanPath(_sourceController.text);
    return sourcePath.isEmpty ? const [] : [sourcePath];
  }

  @override
  void initState() {
    super.initState();
    _workspaceMode = widget.initialPipeline == ProjectPipeline.custom
        ? _WorkspaceMode.manual
        : _WorkspaceMode.automatic;
    _sourceController.addListener(_suggestOutputPath);
    unawaited(_loadEditPresets());
  }

  @override
  void dispose() {
    _renderSubscription?.cancel();
    _sourceController.dispose();
    _outputController.dispose();
    _audioController.dispose();
    _trimStartController.dispose();
    _trimEndController.dispose();
    super.dispose();
  }

  Future<void> _loadEditPresets() async {
    try {
      final presets = await _presetStore.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _savedEditPresets = presets;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not load edit presets: $error';
      });
    }
  }

  AutoEditPreset _currentEditPreset({String? id, String? name}) {
    return AutoEditPreset(
      id: id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name ?? 'Copied edits',
      renderPreset: _preset,
      trimStartSeconds: _readTrimSecondsOrDefault(_trimStartController.text, 0),
      trimEndSeconds: _readOptionalTrimSeconds(_trimEndController.text),
      sourceAudioVolume: _sourceAudioVolume,
      overlayAudioVolume: _overlayAudioVolume,
    );
  }

  double _readTrimSecondsOrDefault(String value, double fallback) {
    final text = value.trim();
    if (text.isEmpty) {
      return fallback;
    }
    return double.tryParse(text) ?? fallback;
  }

  double? _readOptionalTrimSeconds(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(text);
  }

  void _applyEditPreset(AutoEditPreset editPreset) {
    setState(() {
      _preset = editPreset.renderPreset;
      _resolution = _resolutionFor(editPreset.renderPreset.composition);
      _colorStyle = _colorStyleFor(editPreset.renderPreset.composition);
      _sourceAudioVolume = editPreset.sourceAudioVolume.clamp(0, 2).toDouble();
      _overlayAudioVolume = editPreset.overlayAudioVolume
          .clamp(0, 2)
          .toDouble();
      _trimStartController.text = _formatNumber(editPreset.trimStartSeconds);
      _trimEndController.text = editPreset.trimEndSeconds == null
          ? ''
          : _formatNumber(editPreset.trimEndSeconds!);
      _progress = null;
      _status = 'Applied ${editPreset.name}.';
    });
  }

  _OutputResolution _resolutionFor(ShortsCompositionSpec composition) {
    for (final resolution in _OutputResolution.values) {
      if (resolution.width == composition.width &&
          resolution.height == composition.height) {
        return resolution;
      }
    }
    return _OutputResolution.vertical;
  }

  _ColorStyle _colorStyleFor(ShortsCompositionSpec composition) {
    for (final style in _ColorStyle.values) {
      final values = style.values;
      if ((composition.backgroundDarkness - values.backgroundDarkness).abs() <
              0.001 &&
          (composition.backgroundSaturation - values.backgroundSaturation)
                  .abs() <
              0.001 &&
          (composition.foregroundSaturation - values.foregroundSaturation)
                  .abs() <
              0.001 &&
          (composition.contrast - values.contrast).abs() < 0.001 &&
          (composition.gamma - values.gamma).abs() < 0.001) {
        return style;
      }
    }
    return _ColorStyle.natural;
  }

  Future<void> _saveEditPreset() async {
    if (_isRendering) {
      return;
    }
    final name = await _askPresetName();
    if (!mounted || name == null || name.trim().isEmpty) {
      return;
    }

    final editPreset = _currentEditPreset(name: name.trim());
    final nextPresets = [..._savedEditPresets, editPreset];
    try {
      await _presetStore.saveAll(nextPresets);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedEditPresets = nextPresets;
        _status = 'Saved ${editPreset.name}.';
        _progress = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not save edit preset: $error';
        _progress = null;
      });
    }
  }

  Future<String?> _askPresetName() {
    final controller = TextEditingController(
      text: 'Auto edits ${_savedEditPresets.length + 1}',
    );
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Edit Preset'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Preset name',
              prefixIcon: Icon(Icons.bookmark_add_outlined),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _deleteEditPreset(String presetId) async {
    if (_isRendering) {
      return;
    }
    final nextPresets = _savedEditPresets
        .where((preset) => preset.id != presetId)
        .toList(growable: false);
    try {
      await _presetStore.saveAll(nextPresets);
      if (!mounted) {
        return;
      }
      setState(() {
        _savedEditPresets = nextPresets;
        _status = 'Edit preset removed.';
        _progress = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Could not delete edit preset: $error';
        _progress = null;
      });
    }
  }

  void _copyCurrentEdits() {
    if (_isRendering) {
      return;
    }
    setState(() {
      _copiedEditPreset = _currentEditPreset(name: 'Copied edits');
      _status = 'Edits copied.';
      _progress = null;
    });
  }

  void _pasteCopiedEdits() {
    final copied = _copiedEditPreset;
    if (_isRendering || copied == null) {
      return;
    }
    _applyEditPreset(copied);
  }

  void _suggestOutputPath() {
    final sourcePath = _cleanPath(_sourceController.text);
    if (sourcePath.isEmpty) {
      return;
    }

    final suggestedPath = _suggestedOutputPath(sourcePath);
    final outputPath = _cleanPath(_outputController.text);
    if (outputPath.isNotEmpty && outputPath != _autoSuggestedOutputPath) {
      return;
    }

    _autoSuggestedOutputPath = suggestedPath;
    if (_outputController.text != suggestedPath) {
      _outputController.text = suggestedPath;
    }
  }

  String _suggestedOutputPath(String sourcePath) {
    final directory = p.dirname(sourcePath);
    final basename = p.basenameWithoutExtension(sourcePath);
    return p.join(directory, '${basename}_shorts.mp4');
  }

  String _cleanPath(String value) {
    var path = value.trim();
    while (path.length >= 2) {
      final startsWithDoubleQuote = path.startsWith('"');
      final startsWithSingleQuote = path.startsWith("'");
      final endsWithDoubleQuote = path.endsWith('"');
      final endsWithSingleQuote = path.endsWith("'");

      if ((startsWithDoubleQuote && endsWithDoubleQuote) ||
          (startsWithSingleQuote && endsWithSingleQuote)) {
        path = path.substring(1, path.length - 1).trim();
      } else {
        break;
      }
    }
    return path;
  }

  Future<void> _chooseSourceVideo() async {
    if (_isRendering) {
      return;
    }

    try {
      var selectedPaths = await _filePickerChannel.invokeListMethod<String>(
        'pickVideos',
      );
      selectedPaths ??= [
        ?await _filePickerChannel.invokeMethod<String>('pickVideo'),
      ];
      final sourcePaths = selectedPaths
          .map(_cleanPath)
          .where((path) => path.isNotEmpty)
          .toList(growable: false);
      if (!mounted || sourcePaths.isEmpty) {
        return;
      }

      final sourcePath = sourcePaths.first;
      final suggestedPath = _suggestedOutputPath(sourcePath);

      setState(() {
        _sourceController.text = sourcePath;
        for (final path in sourcePaths) {
          if (!_sourceQueue.contains(path)) {
            _sourceQueue.add(path);
          }
        }
        if (_cleanPath(_outputController.text).isEmpty ||
            _cleanPath(_outputController.text) == _autoSuggestedOutputPath) {
          _outputController.text = suggestedPath;
          _autoSuggestedOutputPath = suggestedPath;
        }
        _progress = null;
        _status = sourcePaths.length == 1
            ? 'Video queued.'
            : '${sourcePaths.length} videos queued.';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = null;
        _status = error.message ?? 'Could not open the video picker.';
      });
    }
  }

  void _removeQueuedSource(String sourcePath) {
    if (_isRendering) {
      return;
    }
    setState(() {
      _sourceQueue.remove(sourcePath);
      if (_sourceQueue.isEmpty) {
        _status = 'Queue cleared.';
      } else {
        _sourceController.text = _sourceQueue.first;
        _status = 'Video removed from queue.';
      }
      _progress = null;
    });
  }

  void _clearSourceQueue() {
    if (_isRendering) {
      return;
    }
    setState(() {
      _sourceQueue.clear();
      _progress = null;
      _status = 'Queue cleared.';
    });
  }

  Future<void> _chooseAudio() async {
    if (_isRendering) {
      return;
    }

    try {
      final selectedPath = await _filePickerChannel.invokeMethod<String>(
        'pickAudio',
      );
      if (!mounted || selectedPath == null || selectedPath.trim().isEmpty) {
        return;
      }

      setState(() {
        _audioController.text = _cleanPath(selectedPath);
        _progress = null;
        _status = 'Audio selected.';
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _progress = null;
        _status = error.message ?? 'Could not open the audio picker.';
      });
    }
  }

  void _clearAudio() {
    if (_isRendering) {
      return;
    }

    setState(() {
      _audioController.clear();
      _progress = null;
      _status = 'Audio removed.';
    });
  }

  void _setResolution(_OutputResolution resolution) {
    setState(() {
      final composition = _preset.composition;
      _resolution = resolution;
      _preset = _preset.copyWith(
        composition: composition.copyWith(
          width: resolution.width,
          height: resolution.height,
          foregroundHeight: _defaultForegroundHeight(resolution),
          verticalOffset: 0.5,
        ),
      );
    });
  }

  int _defaultForegroundHeight(_OutputResolution resolution) {
    if (resolution.width > resolution.height) {
      return resolution.height;
    }

    return (resolution.width * 9 / 16)
        .round()
        .clamp(1, resolution.height)
        .toInt();
  }

  void _setForegroundFrame(double foregroundHeightRatio) {
    setState(() {
      final composition = _preset.composition;
      final foregroundHeight = (composition.height * foregroundHeightRatio)
          .round()
          .clamp((composition.height * 0.25).round(), composition.height)
          .toInt();
      _preset = _preset.copyWith(
        composition: composition.copyWith(
          foregroundHeight: foregroundHeight,
          verticalOffset: 0.5,
        ),
      );
    });
  }

  void _setColorStyle(_ColorStyle style) {
    final values = style.values;
    setState(() {
      _preset = _preset.copyWith(
        composition: _preset.composition.copyWith(
          backgroundDarkness: values.backgroundDarkness,
          backgroundSaturation: values.backgroundSaturation,
          foregroundSaturation: values.foregroundSaturation,
          contrast: values.contrast,
          gamma: values.gamma,
        ),
      );
      _colorStyle = style;
    });
  }

  void _setSharpness(double value) {
    setState(() {
      _preset = _preset.copyWith(
        composition: _preset.composition.copyWith(
          sharpness: value.clamp(0, 1).toDouble(),
        ),
      );
    });
  }

  void _setPanningBlur(double value) {
    setState(() {
      _preset = _preset.copyWith(
        exportSettings: _preset.exportSettings.copyWith(
          panningBlurIntensity: value.clamp(0, 1).toDouble(),
        ),
      );
    });
  }

  void _setMotionBlur(bool enabled) {
    setState(() {
      _preset = _preset.copyWith(
        exportSettings: _preset.exportSettings.copyWith(motionBlur: enabled),
      );
    });
  }

  void _setSourceAudioVolume(double value) {
    setState(() {
      _sourceAudioVolume = value.clamp(0, 2).toDouble();
    });
  }

  void _setOverlayAudioVolume(double value) {
    setState(() {
      _overlayAudioVolume = value.clamp(0, 2).toDouble();
    });
  }

  void _setMotionInterpolation(bool enabled) {
    setState(() {
      _preset = _preset.copyWith(
        exportSettings: _preset.exportSettings.copyWith(
          temporalSmoothing: enabled
              ? TemporalSmoothingMode.motionInterpolation
              : TemporalSmoothingMode.fpsConversion,
        ),
      );
    });
  }

  void _setInterpolationQuality(InterpolationQuality quality) {
    setState(() {
      _preset = _preset.copyWith(
        exportSettings: _preset.exportSettings.copyWith(
          interpolationQuality: quality,
        ),
      );
    });
  }

  double? _readTrimSeconds(String value, String label) {
    final text = value.trim();
    if (text.isEmpty) {
      return null;
    }

    final seconds = double.tryParse(text);
    if (seconds == null || seconds < 0) {
      setState(() {
        _progress = null;
        _status = '$label must be a positive number of seconds.';
      });
      return null;
    }
    return seconds;
  }

  Future<void> _render() async {
    final sourcePaths = _renderSourcePaths
        .map(_cleanPath)
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (sourcePaths.isEmpty) {
      setState(() {
        _progress = null;
        _status = 'Choose at least one source video.';
      });
      return;
    }
    final firstSourcePath = sourcePaths.first;
    final outputPath = _cleanPath(_outputController.text);
    final audioPath = _cleanPath(_audioController.text);
    if (_sourceController.text != firstSourcePath) {
      _sourceController.text = firstSourcePath;
    }
    if (_outputController.text != outputPath) {
      _outputController.text = outputPath;
    }
    if (_audioController.text != audioPath) {
      _audioController.text = audioPath;
    }

    final trimStartText = _trimStartController.text.trim();
    final parsedTrimStartSeconds = trimStartText.isEmpty
        ? 0.0
        : _readTrimSeconds(trimStartText, 'Trim start');
    if (trimStartText.isNotEmpty && parsedTrimStartSeconds == null) {
      return;
    }
    final trimStartSeconds = parsedTrimStartSeconds ?? 0.0;
    final trimEndText = _trimEndController.text.trim();
    final trimEndSeconds = trimEndText.isEmpty
        ? null
        : _readTrimSeconds(trimEndText, 'Trim end');
    if (trimEndText.isNotEmpty && trimEndSeconds == null) {
      return;
    }
    if (trimEndSeconds != null && trimEndSeconds <= trimStartSeconds) {
      setState(() {
        _progress = null;
        _status = 'Trim end must be greater than trim start.';
      });
      return;
    }

    if (sourcePaths.length == 1 && outputPath.isEmpty) {
      setState(() {
        _progress = null;
        _status = 'Choose an output path.';
      });
      return;
    }

    final isBatch = sourcePaths.length > 1;
    final jobs = [
      for (var i = 0; i < sourcePaths.length; i++)
        ShortsRenderJob(
          source: VideoAsset(sourcePaths[i]),
          outputPath: _outputPathFor(sourcePaths[i], outputPath, isBatch, i),
          preset: _preset,
          trimStartSeconds: trimStartSeconds,
          trimEndSeconds: trimEndSeconds,
          audioOverlayPath: audioPath.isEmpty ? null : audioPath,
          sourceAudioVolume: _sourceAudioVolume,
          overlayAudioVolume: _overlayAudioVolume,
        ),
    ];

    await _renderSubscription?.cancel();
    setState(() {
      _isRendering = true;
      _progress = 0;
      _lastRenderedOutput = null;
      _status = isBatch ? 'Queued ${jobs.length} videos.' : 'Queued';
    });

    var completed = 0;
    RenderProgress? terminalProgress;
    for (var i = 0; i < jobs.length; i++) {
      if (!mounted) {
        return;
      }
      terminalProgress = await _renderJob(jobs[i], i, jobs.length);
      if (terminalProgress.status != RenderJobStatus.completed) {
        break;
      }
      completed++;
    }

    if (!mounted) {
      return;
    }
    final succeeded = completed == jobs.length;
    setState(() {
      _isRendering = false;
      if (succeeded) {
        _progress = 1;
        _status = isBatch
            ? 'Rendered $completed videos.'
            : terminalProgress?.message ?? 'Render complete.';
      } else {
        _progress = null;
        _status = terminalProgress?.message ?? 'Render stopped.';
      }
    });
    unawaited(
      DesktopNotifier.show(
        title: succeeded ? 'Render complete' : 'Render failed',
        body: succeeded
            ? (isBatch
                  ? '$completed videos are ready to preview and publish.'
                  : '${p.basename(jobs.first.outputPath)} is ready to '
                        'preview and publish.')
            : (terminalProgress?.message ?? 'The render stopped early.'),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          succeeded
              ? 'Render complete — preview it below before publishing.'
              : 'Render failed: ${terminalProgress?.message ?? 'unknown error'}',
        ),
      ),
    );
    }
  }

  String _outputPathFor(
    String sourcePath,
    String requestedOutputPath,
    bool isBatch,
    int index,
  ) {
    if (!isBatch) {
      return requestedOutputPath;
    }

    if (requestedOutputPath.isNotEmpty &&
        p.extension(requestedOutputPath).isEmpty) {
      final basename = p.basenameWithoutExtension(sourcePath);
      return p.join(requestedOutputPath, '${basename}_shorts.mp4');
    }

    final suggestedPath = _suggestedOutputPath(sourcePath);
    if (!File(suggestedPath).existsSync()) {
      return suggestedPath;
    }

    final directory = p.dirname(suggestedPath);
    final basename = p.basenameWithoutExtension(sourcePath);
    return p.join(directory, '${basename}_shorts_${index + 1}.mp4');
  }

  Future<RenderProgress> _renderJob(
    ShortsRenderJob job,
    int index,
    int total,
  ) async {
    final completer = Completer<RenderProgress>();
    await _renderSubscription?.cancel();
    _renderSubscription = _exportUseCase(job).listen(
      (progress) {
        if (mounted) {
          final fraction = progress.fraction;
          setState(() {
            _progress = fraction == null ? null : (index + fraction) / total;
            _status = total == 1
                ? progress.message
                : '${index + 1}/$total ${p.basename(job.source.path)}: '
                      '${progress.message}';
            if (progress.status == RenderJobStatus.completed &&
                progress.outputPath != null) {
              _lastRenderedOutput = progress.outputPath;
            }
          });
        }
        if (progress.isTerminal && !completer.isCompleted) {
          completer.complete(progress);
        }
      },
      onError: (Object error) {
        final failed = RenderProgress(
          status: RenderJobStatus.failed,
          message: '$error',
        );
        if (mounted) {
          setState(() {
            _status = failed.message;
            _progress = null;
          });
        }
        if (!completer.isCompleted) {
          completer.complete(failed);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete(
            const RenderProgress(
              status: RenderJobStatus.failed,
              message: 'Render ended before reporting completion.',
            ),
          );
        }
      },
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    final desktopRendererAvailable =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    final projectName = widget.projectName;

    return Scaffold(
      appBar: AppBar(
        title: Text(projectName ?? 'Content Maker'),
        actions: [
          if (_workspaceMode == _WorkspaceMode.automatic)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_preset.composition.width}x${_preset.composition.height} @ ${_preset.exportSettings.frameRate}fps',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Connected accounts',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => AccountsDialog.show(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _ModeSwitcher(
                selectedMode: _workspaceMode,
                onChanged: (mode) {
                  setState(() {
                    _workspaceMode = mode;
                  });
                },
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _workspaceMode == _WorkspaceMode.automatic
                    ? _buildAutomaticWorkspace(desktopRendererAvailable)
                    : ManualEditorScreen(
                        key: const ValueKey('manual-editor'),
                        desktopRendererAvailable: desktopRendererAvailable,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomaticWorkspace(bool desktopRendererAvailable) {
    return LayoutBuilder(
      key: const ValueKey('automatic-renderer'),
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final controls = _ControlsPanel(
          sourceController: _sourceController,
          outputController: _outputController,
          audioController: _audioController,
          trimStartController: _trimStartController,
          trimEndController: _trimEndController,
          queuedSources: _sourceQueue,
          savedEditPresets: _savedEditPresets,
          hasCopiedEdits: _copiedEditPreset != null,
          isRendering: _isRendering,
          canRender: _canRender && desktopRendererAvailable,
          canChooseSource: Platform.isWindows && !_isRendering,
          canChooseAudio: Platform.isWindows && !_isRendering,
          resolution: _resolution,
          colorStyle: _colorStyle,
          sharpness: _preset.composition.sharpness,
          panningBlurIntensity: _preset.exportSettings.panningBlurIntensity,
          sourceAudioVolume: _sourceAudioVolume,
          overlayAudioVolume: _overlayAudioVolume,
          motionBlurEnabled: _preset.exportSettings.motionBlur,
          motionInterpolationEnabled:
              _preset.exportSettings.temporalSmoothing ==
              TemporalSmoothingMode.motionInterpolation,
          interpolationQuality: _preset.exportSettings.interpolationQuality,
          onInterpolationQualityChanged: _setInterpolationQuality,
          onResolutionChanged: _setResolution,
          onColorStyleChanged: _setColorStyle,
          onSharpnessChanged: _setSharpness,
          onPanningBlurChanged: _setPanningBlur,
          onSourceAudioVolumeChanged: _setSourceAudioVolume,
          onOverlayAudioVolumeChanged: _setOverlayAudioVolume,
          onMotionBlurChanged: _setMotionBlur,
          onMotionInterpolationChanged: _setMotionInterpolation,
          onChooseSource: _chooseSourceVideo,
          onRemoveQueuedSource: _removeQueuedSource,
          onClearSourceQueue: _clearSourceQueue,
          onChooseAudio: _chooseAudio,
          onClearAudio: _clearAudio,
          onSaveEditPreset: _saveEditPreset,
          onApplyEditPreset: _applyEditPreset,
          onDeleteEditPreset: _deleteEditPreset,
          onCopyEdits: _copyCurrentEdits,
          onPasteEdits: _pasteCopiedEdits,
          onRender: _render,
          status: _status,
          progress: _progress,
          desktopRendererAvailable: desktopRendererAvailable,
        );
        final preview = _PreviewPanel(
          preset: _preset,
          onFrameChanged: _isRendering ? null : _setForegroundFrame,
        );

        final workspace = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: controls),
                  const SizedBox(width: 20),
                  Expanded(flex: 4, child: preview),
                ],
              )
            : Column(children: [controls, const SizedBox(height: 20), preview]);

        final renderedOutput = _lastRenderedOutput;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              workspace,
              if (renderedOutput != null) ...[
                const SizedBox(height: 20),
                _PanelCard(
                  child: RenderedClipPlayer(
                    key: ValueKey('player-$renderedOutput'),
                    videoPath: renderedOutput,
                  ),
                ),
                const SizedBox(height: 20),
                PublishPanel(
                  key: ValueKey(renderedOutput),
                  videoPath: renderedOutput,
                  defaultTitle: p.basenameWithoutExtension(renderedOutput),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.selectedMode, required this.onChanged});

  final _WorkspaceMode selectedMode;
  final ValueChanged<_WorkspaceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<_WorkspaceMode>(
          showSelectedIcon: false,
          segments: [
            for (final mode in _WorkspaceMode.values)
              ButtonSegment(
                value: mode,
                icon: Icon(mode.icon),
                label: Text(mode.label),
              ),
          ],
          selected: {selectedMode},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.sourceController,
    required this.outputController,
    required this.audioController,
    required this.trimStartController,
    required this.trimEndController,
    required this.queuedSources,
    required this.savedEditPresets,
    required this.hasCopiedEdits,
    required this.isRendering,
    required this.canRender,
    required this.canChooseSource,
    required this.canChooseAudio,
    required this.resolution,
    required this.colorStyle,
    required this.sharpness,
    required this.panningBlurIntensity,
    required this.sourceAudioVolume,
    required this.overlayAudioVolume,
    required this.motionBlurEnabled,
    required this.motionInterpolationEnabled,
    required this.interpolationQuality,
    required this.onInterpolationQualityChanged,
    required this.onResolutionChanged,
    required this.onColorStyleChanged,
    required this.onSharpnessChanged,
    required this.onPanningBlurChanged,
    required this.onSourceAudioVolumeChanged,
    required this.onOverlayAudioVolumeChanged,
    required this.onMotionBlurChanged,
    required this.onMotionInterpolationChanged,
    required this.onChooseSource,
    required this.onRemoveQueuedSource,
    required this.onClearSourceQueue,
    required this.onChooseAudio,
    required this.onClearAudio,
    required this.onSaveEditPreset,
    required this.onApplyEditPreset,
    required this.onDeleteEditPreset,
    required this.onCopyEdits,
    required this.onPasteEdits,
    required this.onRender,
    required this.status,
    required this.progress,
    required this.desktopRendererAvailable,
  });

  final TextEditingController sourceController;
  final TextEditingController outputController;
  final TextEditingController audioController;
  final TextEditingController trimStartController;
  final TextEditingController trimEndController;
  final List<String> queuedSources;
  final List<AutoEditPreset> savedEditPresets;
  final bool hasCopiedEdits;
  final bool isRendering;
  final bool canRender;
  final bool canChooseSource;
  final bool canChooseAudio;
  final _OutputResolution resolution;
  final _ColorStyle colorStyle;
  final double sharpness;
  final double panningBlurIntensity;
  final double sourceAudioVolume;
  final double overlayAudioVolume;
  final bool motionBlurEnabled;
  final bool motionInterpolationEnabled;
  final InterpolationQuality interpolationQuality;
  final ValueChanged<InterpolationQuality> onInterpolationQualityChanged;
  final ValueChanged<_OutputResolution> onResolutionChanged;
  final ValueChanged<_ColorStyle> onColorStyleChanged;
  final ValueChanged<double> onSharpnessChanged;
  final ValueChanged<double> onPanningBlurChanged;
  final ValueChanged<double> onSourceAudioVolumeChanged;
  final ValueChanged<double> onOverlayAudioVolumeChanged;
  final ValueChanged<bool> onMotionBlurChanged;
  final ValueChanged<bool> onMotionInterpolationChanged;
  final VoidCallback onChooseSource;
  final ValueChanged<String> onRemoveQueuedSource;
  final VoidCallback onClearSourceQueue;
  final VoidCallback onChooseAudio;
  final VoidCallback onClearAudio;
  final VoidCallback onSaveEditPreset;
  final ValueChanged<AutoEditPreset> onApplyEditPreset;
  final ValueChanged<String> onDeleteEditPreset;
  final VoidCallback onCopyEdits;
  final VoidCallback onPasteEdits;
  final VoidCallback onRender;
  final String status;
  final double? progress;
  final bool desktopRendererAvailable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Renderer',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: sourceController,
              decoration: const InputDecoration(
                labelText: 'Selected video',
                prefixIcon: Icon(Icons.video_file_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: canChooseSource ? onChooseSource : null,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Add Videos'),
              ),
            ),
            if (queuedSources.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Queue (${queuedSources.length})',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: isRendering ? null : onClearSourceQueue,
                    icon: const Icon(Icons.clear_all_outlined),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...[
                for (final sourcePath in queuedSources)
                  _QueueSourceTile(
                    sourcePath: sourcePath,
                    onRemove: isRendering
                        ? null
                        : () => onRemoveQueuedSource(sourcePath),
                  ),
              ],
            ],
            const SizedBox(height: 14),
            TextField(
              controller: outputController,
              decoration: const InputDecoration(
                labelText: 'Output mp4 path or batch folder',
                prefixIcon: Icon(Icons.save_alt_outlined),
              ),
            ),
            const SizedBox(height: 18),
            Text('Canvas', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            SegmentedButton<_OutputResolution>(
              segments: [
                for (final option in _OutputResolution.values)
                  ButtonSegment(
                    value: option,
                    icon: Icon(option.icon),
                    label: Text(option.label),
                  ),
              ],
              selected: {resolution},
              onSelectionChanged: isRendering
                  ? null
                  : (selection) => onResolutionChanged(selection.first),
            ),
            const SizedBox(height: 18),
            Text('Trim', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: trimStartController,
                    enabled: !isRendering,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Start seconds',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: trimEndController,
                    enabled: !isRendering,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'End seconds',
                      prefixIcon: Icon(Icons.flag_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Audio', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(
              controller: audioController,
              enabled: !isRendering,
              decoration: const InputDecoration(
                labelText: 'Uploaded audio',
                prefixIcon: Icon(Icons.audio_file_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: canChooseAudio ? onChooseAudio : null,
                  icon: const Icon(Icons.library_music_outlined),
                  label: const Text('Add Audio'),
                ),
                TextButton.icon(
                  onPressed: isRendering ? null : onClearAudio,
                  icon: const Icon(Icons.close_outlined),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ControlSlider(
              icon: Icons.volume_up_outlined,
              label: 'Original track',
              value: sourceAudioVolume,
              min: 0,
              max: 2,
              divisions: 20,
              displayValue: '${(sourceAudioVolume * 100).round()}%',
              onChanged: isRendering ? null : onSourceAudioVolumeChanged,
            ),
            _ControlSlider(
              icon: Icons.music_note_outlined,
              label: 'Uploaded audio',
              value: overlayAudioVolume,
              min: 0,
              max: 2,
              divisions: 20,
              displayValue: '${(overlayAudioVolume * 100).round()}%',
              onChanged: isRendering ? null : onOverlayAudioVolumeChanged,
            ),
            const SizedBox(height: 18),
            Text('Look', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: isRendering ? null : onCopyEdits,
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Copy Edits'),
                ),
                OutlinedButton.icon(
                  onPressed: !isRendering && hasCopiedEdits
                      ? onPasteEdits
                      : null,
                  icon: const Icon(Icons.content_paste_outlined),
                  label: const Text('Paste Edits'),
                ),
                OutlinedButton.icon(
                  onPressed: isRendering ? null : onSaveEditPreset,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save Preset'),
                ),
              ],
            ),
            if (savedEditPresets.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final editPreset in savedEditPresets)
                    InputChip(
                      avatar: const Icon(Icons.bookmark_outline, size: 18),
                      label: Text(editPreset.name),
                      onPressed: isRendering
                          ? null
                          : () => onApplyEditPreset(editPreset),
                      onDeleted: isRendering
                          ? null
                          : () => onDeleteEditPreset(editPreset.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in _ColorStyle.values)
                  ChoiceChip(
                    avatar: Icon(style.icon, size: 18),
                    label: Text(style.label),
                    selected: colorStyle == style,
                    onSelected: isRendering
                        ? null
                        : (_) => onColorStyleChanged(style),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _ControlSlider(
              icon: Icons.tune_outlined,
              label: 'Sharpness',
              value: sharpness,
              min: 0,
              max: 1,
              divisions: 20,
              displayValue: '${(sharpness * 100).round()}%',
              onChanged: isRendering ? null : onSharpnessChanged,
            ),
            _ControlSlider(
              icon: Icons.blur_linear_outlined,
              label: 'Background panning blur',
              value: panningBlurIntensity,
              min: 0,
              max: 1,
              divisions: 20,
              displayValue: '${(panningBlurIntensity * 100).round()}%',
              onChanged: isRendering ? null : onPanningBlurChanged,
            ),
            Material(
              color: Colors.transparent,
              child: Column(
                children: [
                  SwitchListTile(
                    value: motionBlurEnabled,
                    onChanged: isRendering ? null : onMotionBlurChanged,
                    title: const Text('Background frame blur'),
                    secondary: const Icon(Icons.motion_photos_on_outlined),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    value: motionInterpolationEnabled,
                    onChanged: isRendering
                        ? null
                        : onMotionInterpolationChanged,
                    title: const Text('Motion interpolation'),
                    subtitle: Text(
                      motionInterpolationEnabled
                          ? 'Smooths motion to the target frame rate'
                          : 'Off — fastest export',
                    ),
                    secondary: const Icon(Icons.slow_motion_video_outlined),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (motionInterpolationEnabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const SizedBox(width: 34),
                          Expanded(
                            child: SegmentedButton<InterpolationQuality>(
                              showSelectedIcon: false,
                              segments: [
                                for (final quality
                                    in InterpolationQuality.values)
                                  ButtonSegment(
                                    value: quality,
                                    label: Text(quality.label),
                                  ),
                              ],
                              selected: {interpolationQuality},
                              onSelectionChanged: isRendering
                                  ? null
                                  : (selection) =>
                                        onInterpolationQualityChanged(
                                          selection.first,
                                        ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (!desktopRendererAvailable)
              const _StatusBanner(
                icon: Icons.desktop_windows_outlined,
                text: 'Desktop FFmpeg rendering is wired first.',
              ),
            FilledButton.icon(
              onPressed: canRender ? onRender : null,
              icon: isRendering
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.movie_creation_outlined),
              label: Text(isRendering ? 'Rendering' : 'Render Short'),
            ),
            const SizedBox(height: 16),
            if (isRendering || progress != null) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 10),
            ],
            Text(
              status,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFFD0D0D0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueSourceTile extends StatelessWidget {
  const _QueueSourceTile({required this.sourcePath, required this.onRemove});

  final String sourcePath;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(
                Icons.movie_creation_outlined,
                color: Color(0xFF9CC4CE),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.basename(sourcePath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                tooltip: 'Remove from queue',
                icon: const Icon(Icons.close_outlined, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlSlider extends StatelessWidget {
  const _ControlSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: const Color(0xFFD0D0D0)),
              const SizedBox(width: 10),
              Expanded(child: Text(label)),
              Text(
                displayValue,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFD0D0D0),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.preset, required this.onFrameChanged});

  final RenderPreset preset;
  final ValueChanged<double>? onFrameChanged;

  @override
  Widget build(BuildContext context) {
    final composition = preset.composition;
    final topBand = composition.foregroundY / composition.height;
    final foreground = composition.foregroundHeight / composition.height;
    final aspectRatio = composition.width / composition.height;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF303030)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              preset.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 560),
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LayoutBuilder(
                      builder: (context, previewConstraints) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            const _BlurPreviewBackground(),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: previewConstraints.maxHeight * topBand,
                              height: previewConstraints.maxHeight * foreground,
                              child: _CenteredForegroundPreview(
                                foregroundRatio: foreground,
                                previewHeight: previewConstraints.maxHeight,
                                onFrameChanged: onFrameChanged,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SpecChip(
                  icon: composition.width > composition.height
                      ? Icons.crop_16_9_outlined
                      : composition.width == composition.height
                      ? Icons.crop_square_outlined
                      : Icons.crop_portrait_outlined,
                  label: '${composition.width}x${composition.height}',
                ),
                _SpecChip(
                  icon: Icons.blur_on_outlined,
                  label: 'Blur ${composition.blurSigma.toStringAsFixed(0)}',
                ),
                _SpecChip(
                  icon: Icons.speed_outlined,
                  label: '${preset.exportSettings.frameRate}fps',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurPreviewBackground extends StatelessWidget {
  const _BlurPreviewBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF262626),
            Color(0xFF191919),
            Color(0xFF303030),
            Color(0xFF111111),
          ],
        ),
      ),
      child: Container(color: const Color(0x66000000)),
    );
  }
}

class _CenteredForegroundPreview extends StatelessWidget {
  const _CenteredForegroundPreview({
    required this.foregroundRatio,
    required this.previewHeight,
    required this.onFrameChanged,
  });

  final double foregroundRatio;
  final double previewHeight;
  final ValueChanged<double>? onFrameChanged;

  void _resizeFrame(DragUpdateDetails details) {
    final onFrameChanged = this.onFrameChanged;
    if (onFrameChanged == null) {
      return;
    }

    final currentHeight = previewHeight * foregroundRatio;
    final nextHeight = (currentHeight + details.delta.dy).clamp(
      previewHeight * 0.35,
      previewHeight,
    );
    onFrameChanged(nextHeight / previewHeight);
  }

  @override
  Widget build(BuildContext context) {
    final canDrag = onFrameChanged != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        const _ForegroundPreview(),
        if (canDrag)
          Align(
            alignment: Alignment.bottomCenter,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: _resizeFrame,
                child: Container(
                  height: 28,
                  alignment: Alignment.center,
                  color: const Color(0x33000000),
                  child: const Icon(
                    Icons.drag_handle,
                    color: Color(0xDDFFFFFF),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ForegroundPreview extends StatelessWidget {
  const _ForegroundPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0x66FFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3A3A3A),
            Color(0xFF202020),
            Color(0xFF323232),
            Color(0xFF171717),
          ],
        ),
      ),
      child: const Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Icon(
              Icons.control_camera_outlined,
              size: 44,
              color: Color(0xDDFFFFFF),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatNumber(num value) {
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
