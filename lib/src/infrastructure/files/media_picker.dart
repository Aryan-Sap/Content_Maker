import 'dart:io';

import 'package:flutter/services.dart';

/// Uses the native document picker exposed by each platform runner.
///
/// Android selections are copied into app-private persistent storage by the
/// runner so saved projects and FFmpeg always receive a normal, readable path.
abstract final class MediaPicker {
  static const _channel = MethodChannel('content_maker/file_picker');

  static Future<List<String>> videos({bool multiple = true}) async {
    if (multiple) {
      final paths = await _channel.invokeListMethod<String>('pickVideos');
      if (paths != null) return paths;
    }
    final path = await _channel.invokeMethod<String>('pickVideo');
    return path == null ? const [] : [path];
  }

  static Future<String?> audio() => _channel.invokeMethod<String>('pickAudio');

  static Future<String?> project({bool save = false}) async {
    if ((Platform.isAndroid || Platform.isIOS) && save) {
      return null;
    }
    return _channel.invokeMethod<String>(save ? 'saveProject' : 'pickProject');
  }
}
