import '../../domain/rendering/concat_merge_job.dart';
import 'ffmpeg_segment_normalizer.dart';

class FfmpegConcatCommandBuilder {
  const FfmpegConcatCommandBuilder({
    this.segmentNormalizer = const FfmpegSegmentNormalizer(),
  });

  static const audioSampleRate = 48000;

  final FfmpegSegmentNormalizer segmentNormalizer;

  List<String> build(ConcatMergeJob job) {
    final inputLabels = _inputLabels(job);
    final preset = job.preset;

    return <String>[
      '-y',
      '-hide_banner',
      '-nostats',
      for (var i = 0; i < job.inputs.length; i++) ...[
        '-i',
        job.inputs[i].path,
        if (!job.inputs[i].hasAudio) ...[
          '-f',
          'lavfi',
          '-t',
          _number(job.inputs[i].trimDurationSeconds),
          '-i',
          'anullsrc=channel_layout=stereo:sample_rate=$audioSampleRate',
        ],
      ],
      '-filter_complex',
      _buildFilterGraph(job, inputLabels),
      '-map',
      '[outv]',
      '-map',
      '[outa]',
      '-c:v',
      preset.exportSettings.videoCodec,
      '-preset',
      preset.exportSettings.encoderPreset,
      '-crf',
      '${preset.exportSettings.crf}',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      preset.exportSettings.audioBitrate,
      '-movflags',
      '+faststart',
      '-progress',
      'pipe:1',
      job.outputPath,
    ];
  }

  String buildFilterGraph(ConcatMergeJob job) {
    return _buildFilterGraph(job, _inputLabels(job));
  }

  String _buildFilterGraph(
    ConcatMergeJob job,
    List<_ConcatInputLabels> inputLabels,
  ) {
    final labels = inputLabels;
    final graph = StringBuffer();
    final composition = job.preset.composition;
    final frameRate = job.preset.exportSettings.frameRate;

    for (var i = 0; i < job.inputs.length; i++) {
      final input = job.inputs[i];
      final label = labels[i];
      if (i > 0) {
        graph.write(';');
      }
      graph.write(
        segmentNormalizer.normalizedVideoSegment(
          width: composition.width,
          height: composition.height,
          fps: frameRate,
          inLabel: '${label.videoInputIndex}:v',
          outLabel: 'v$i',
          trimStartSeconds: input.trimStartSeconds,
          trimDurationSeconds: input.trimDurationSeconds,
        ),
      );
      graph.write(';');
      graph.write(
        segmentNormalizer.normalizedAudioSegment(
          sampleRate: audioSampleRate,
          inLabel: '${label.audioInputIndex}:a',
          outLabel: 'a$i',
          trimStartSeconds: input.hasAudio ? input.trimStartSeconds : 0,
          trimDurationSeconds: input.hasAudio
              ? input.trimDurationSeconds
              : null,
        ),
      );
    }

    graph.write(';');
    for (var i = 0; i < job.inputs.length; i++) {
      graph.write('[v$i][a$i]');
    }
    graph.write('concat=n=${job.inputs.length}:v=1:a=1[outv][outa]');

    return graph.toString();
  }

  List<_ConcatInputLabels> _inputLabels(ConcatMergeJob job) {
    final labels = <_ConcatInputLabels>[];
    var ffmpegInputIndex = 0;

    for (final input in job.inputs) {
      final videoInputIndex = ffmpegInputIndex;
      var audioInputIndex = ffmpegInputIndex;
      ffmpegInputIndex++;
      if (!input.hasAudio) {
        audioInputIndex = ffmpegInputIndex;
        ffmpegInputIndex++;
      }
      labels.add(
        _ConcatInputLabels(
          videoInputIndex: videoInputIndex,
          audioInputIndex: audioInputIndex,
        ),
      );
    }

    return labels;
  }

  String _number(num value) {
    final text = value.toStringAsFixed(3);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _ConcatInputLabels {
  const _ConcatInputLabels({
    required this.videoInputIndex,
    required this.audioInputIndex,
  });

  final int videoInputIndex;
  final int audioInputIndex;
}
