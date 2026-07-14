import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the `ffmpeg` / `ffprobe` executables the app should invoke.
///
/// A distributed build cannot assume end users have FFmpeg installed, so the
/// binaries are shipped with the app. Resolution order:
///
/// 1. `FFMPEG_LOCATION` environment variable (a directory), if set.
/// 2. Next to the running executable (where the MSIX/release build ships them).
/// 3. A `ffmpeg/` subfolder next to the running executable.
/// 4. Bare tool name, i.e. rely on the system PATH (dev machines, tests).
class FfmpegExecutables {
  const FfmpegExecutables._();

  static String get ffmpeg => _resolve('ffmpeg');
  static String get ffprobe => _resolve('ffprobe');
  static String get ffplay => _resolve('ffplay');

  static String _resolve(String tool) {
    final exeName = Platform.isWindows ? '$tool.exe' : tool;

    final override = Platform.environment['FFMPEG_LOCATION'];
    if (override != null && override.trim().isNotEmpty) {
      final candidate = File(p.join(override.trim(), exeName));
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }

    Directory appDir;
    try {
      appDir = File(Platform.resolvedExecutable).parent;
    } on Object {
      return tool;
    }

    for (final candidate in [
      File(p.join(appDir.path, exeName)),
      File(p.join(appDir.path, 'ffmpeg', exeName)),
    ]) {
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }

    // Fall back to PATH.
    return tool;
  }
}
