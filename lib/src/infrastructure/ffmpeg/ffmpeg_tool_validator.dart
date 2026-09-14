import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'ffmpeg_executables.dart';

class FfmpegToolValidator {
  const FfmpegToolValidator();

  Future<String?> validate({bool requireFfprobe = true}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final session = await FFmpegKit.executeWithArguments(const [
          '-version',
        ]);
        return ReturnCode.isSuccess(await session.getReturnCode())
            ? null
            : 'The mobile video engine could not start.';
      } on Object {
        return 'The mobile video engine could not start.';
      }
    }
    final ffmpegError = await _validateTool(FfmpegExecutables.ffmpeg);
    if (ffmpegError != null) {
      return ffmpegError;
    }

    if (requireFfprobe) {
      final ffprobeError = await _validateTool(FfmpegExecutables.ffprobe);
      if (ffprobeError != null) {
        return ffprobeError;
      }
    }

    return null;
  }

  Future<String?> _validateTool(String executable) async {
    try {
      final result = await Process.run(executable, <String>[
        '-version',
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        return null;
      }

      return '$executable is installed but failed to start. '
          'Make sure FFmpeg is installed and available on PATH.';
    } on Object {
      return '$executable was not found. Install FFmpeg and make sure '
          'ffmpeg and ffprobe are available on PATH.';
    }
  }
}
