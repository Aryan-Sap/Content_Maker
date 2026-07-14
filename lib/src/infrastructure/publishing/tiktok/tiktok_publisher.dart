import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/publish_job.dart';
import '../../../domain/publishing/publish_metadata.dart';
import '../../../domain/publishing/publish_target.dart';
import '../../../domain/publishing/video_publisher.dart';

/// Publishes a rendered video to TikTok via the Content Posting API using the
/// Direct Post + `FILE_UPLOAD` flow.
///
/// Until the developer app passes TikTok's audit, only `SELF_ONLY` visibility
/// is permitted, so posts land privately/in drafts. The API path is identical
/// once audited — only the allowed privacy levels widen.
class TiktokPublisher implements VideoPublisher {
  TiktokPublisher({
    http.Client? client,
    this.chunkSize = _defaultChunkSize,
    this.pollInterval = const Duration(seconds: 2),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// TikTok requires chunks between 5 MiB and 64 MiB (a whole video under the
  /// chunk size is sent as a single chunk).
  final int chunkSize;

  final Duration pollInterval;

  static const int _defaultChunkSize = 32 * 1024 * 1024;
  static const int _minChunkSize = 5 * 1024 * 1024;
  static const int _maxChunkSize = 64 * 1024 * 1024;
  static const String _base = 'https://open.tiktokapis.com/v2';

  @override
  PublishTarget get target => PublishTarget.tiktok;

  /// Maps requested privacy to a TikTok `privacy_level`. Clamped to
  /// [allowedLevels] when the creator-info query provides them.
  static String privacyLevel(
    PublishPrivacy privacy, {
    List<String> allowedLevels = const [],
  }) {
    final requested = switch (privacy) {
      PublishPrivacy.public => 'PUBLIC_TO_EVERYONE',
      PublishPrivacy.unlisted ||
      PublishPrivacy.private ||
      PublishPrivacy.draft => 'SELF_ONLY',
    };
    if (allowedLevels.isEmpty || allowedLevels.contains(requested)) {
      return requested;
    }
    // Prefer the most private allowed option when the requested one is blocked
    // (typical for unaudited apps).
    return allowedLevels.contains('SELF_ONLY')
        ? 'SELF_ONLY'
        : allowedLevels.first;
  }

  /// Builds the `post/publish/video/init` request body. Extracted for testing.
  Map<String, dynamic> buildInitRequest({
    required PublishMetadata metadata,
    required int videoSize,
    required int chunkSize,
    required int totalChunkCount,
    List<String> allowedLevels = const [],
  }) {
    return {
      'post_info': {
        'title': metadata.caption,
        'privacy_level': privacyLevel(
          metadata.privacy,
          allowedLevels: allowedLevels,
        ),
        'disable_duet': false,
        'disable_comment': false,
        'disable_stitch': false,
        'brand_content_toggle': false,
        'brand_organic_toggle': false,
      },
      'source_info': {
        'source': 'FILE_UPLOAD',
        'video_size': videoSize,
        'chunk_size': chunkSize,
        'total_chunk_count': totalChunkCount,
      },
    };
  }

  @override
  Stream<PublishProgress> publish(
    PublishJob job,
    OAuthCredentials credentials,
  ) {
    final controller = StreamController<PublishProgress>();
    _run(job, credentials, controller);
    return controller.stream;
  }

  Future<void> _run(
    PublishJob job,
    OAuthCredentials credentials,
    StreamController<PublishProgress> controller,
  ) async {
    void emit(PublishProgress progress) {
      if (!controller.isClosed) {
        controller.add(progress);
      }
    }

    try {
      final file = File(job.videoPath);
      if (!file.existsSync()) {
        emit(_fail('Rendered file was not found: ${job.videoPath}'));
        return;
      }
      final totalBytes = await file.length();
      if (totalBytes == 0) {
        emit(_fail('Rendered file is empty: ${job.videoPath}'));
        return;
      }
      final chunkPlan = TiktokChunkPlan.forVideo(
        videoSize: totalBytes,
        preferredChunkSize: chunkSize,
      );

      emit(
        PublishProgress(
          target: target,
          status: PublishJobStatus.uploading,
          fraction: 0,
          message: 'Starting TikTok upload.',
        ),
      );

      final allowedLevels = await _fetchAllowedPrivacyLevels(
        credentials.accessToken,
      );

      final init = await _initUpload(
        credentials.accessToken,
        buildInitRequest(
          metadata: job.metadata,
          videoSize: totalBytes,
          chunkSize: chunkPlan.chunkSize,
          totalChunkCount: chunkPlan.totalChunkCount,
          allowedLevels: allowedLevels,
        ),
      );

      await _uploadChunks(
        file: file,
        totalBytes: totalBytes,
        chunkPlan: chunkPlan,
        uploadUrl: init.uploadUrl,
        onProgress: (sent) => emit(
          PublishProgress(
            target: target,
            status: PublishJobStatus.uploading,
            fraction: totalBytes == 0 ? null : sent / totalBytes,
            message: 'Uploading to TikTok.',
          ),
        ),
      );

      emit(
        PublishProgress(
          target: target,
          status: PublishJobStatus.processing,
          fraction: 1,
          message: 'TikTok is processing the video.',
        ),
      );

      final result = await _pollStatus(credentials.accessToken, init.publishId);

      emit(result);
    } catch (error) {
      emit(_fail('$error'));
    } finally {
      await controller.close();
    }
  }

  Future<List<String>> _fetchAllowedPrivacyLevels(String accessToken) async {
    try {
      final response = await _client.post(
        Uri.parse('$_base/post/publish/creator_info/query/'),
        headers: _jsonHeaders(accessToken),
      );
      if (response.statusCode != 200) {
        return const [];
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final options = data?['privacy_level_options'] as List?;
      return options?.map((e) => e.toString()).toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  Future<_TiktokInit> _initUpload(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      Uri.parse('$_base/post/publish/video/init/'),
      headers: _jsonHeaders(accessToken),
      body: jsonEncode(body),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    _throwOnError(json, 'TikTok upload could not start');
    final data = json['data'] as Map<String, dynamic>?;
    final publishId = data?['publish_id'] as String?;
    final uploadUrl = data?['upload_url'] as String?;
    if (publishId == null || uploadUrl == null) {
      throw Exception('TikTok init returned no upload URL.');
    }
    return _TiktokInit(publishId: publishId, uploadUrl: uploadUrl);
  }

  Future<void> _uploadChunks({
    required File file,
    required int totalBytes,
    required TiktokChunkPlan chunkPlan,
    required String uploadUrl,
    required void Function(int sent) onProgress,
  }) async {
    final handle = await file.open();
    try {
      var offset = 0;
      for (var index = 0; index < chunkPlan.totalChunkCount; index++) {
        final isLast = index == chunkPlan.totalChunkCount - 1;
        final end = isLast
            ? totalBytes
            : math.min(offset + chunkPlan.chunkSize, totalBytes);
        await handle.setPosition(offset);
        final bytes = await handle.read(end - offset);

        final response = await _client.put(
          Uri.parse(uploadUrl),
          headers: {
            'Content-Type': 'video/mp4',
            'Content-Length': '${end - offset}',
            'Content-Range': 'bytes $offset-${end - 1}/$totalBytes',
          },
          body: bytes,
        );

        if (response.statusCode != 200 &&
            response.statusCode != 201 &&
            response.statusCode != 206) {
          throw Exception('TikTok chunk upload failed: ${response.body}');
        }
        offset = end;
        onProgress(offset);
      }
    } finally {
      await handle.close();
    }
  }

  Future<PublishProgress> _pollStatus(
    String accessToken,
    String publishId,
  ) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(pollInterval);
      final response = await _client.post(
        Uri.parse('$_base/post/publish/status/fetch/'),
        headers: _jsonHeaders(accessToken),
        body: jsonEncode({'publish_id': publishId}),
      );
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      _throwOnError(json, 'TikTok publish failed');
      final data = json['data'] as Map<String, dynamic>?;
      final status = data?['status'] as String?;

      switch (status) {
        case 'PUBLISH_COMPLETE':
          final postId = (data?['publicaly_available_post_id'] as List?)
              ?.map((e) => e.toString())
              .firstOrNull;
          return PublishProgress(
            target: target,
            status: PublishJobStatus.completed,
            fraction: 1,
            message: 'Published to TikTok.',
            postId: postId ?? publishId,
          );
        case 'FAILED':
          return _fail(
            'TikTok reported the upload failed: ${data?['fail_reason'] ?? 'unknown'}',
          );
        default:
          // PROCESSING_UPLOAD / PROCESSING_DOWNLOAD / SEND_TO_USER_INBOX etc.
          continue;
      }
    }
    // Upload accepted but not confirmed public within the poll window. For
    // unaudited apps the video is delivered to the creator's inbox/drafts.
    return PublishProgress(
      target: target,
      status: PublishJobStatus.completed,
      fraction: 1,
      message:
          'Uploaded to TikTok. Finish posting from the TikTok app '
          '(inbox/drafts) if it does not appear automatically.',
      postId: publishId,
    );
  }

  Map<String, String> _jsonHeaders(String accessToken) => {
    'Authorization': 'Bearer $accessToken',
    'Content-Type': 'application/json; charset=UTF-8',
  };

  void _throwOnError(Map<String, dynamic> json, String context) {
    final error = json['error'] as Map<String, dynamic>?;
    final code = error?['code'] as String?;
    if (code != null && code != 'ok') {
      throw Exception('$context: ${error?['message'] ?? code}');
    }
  }

  PublishProgress _fail(String message) {
    return PublishProgress(
      target: target,
      status: PublishJobStatus.failed,
      message: message,
    );
  }
}

class _TiktokInit {
  const _TiktokInit({required this.publishId, required this.uploadUrl});

  final String publishId;
  final String uploadUrl;
}

class TiktokChunkPlan {
  const TiktokChunkPlan({
    required this.videoSize,
    required this.chunkSize,
    required this.totalChunkCount,
  });

  final int videoSize;
  final int chunkSize;
  final int totalChunkCount;

  static TiktokChunkPlan forVideo({
    required int videoSize,
    required int preferredChunkSize,
  }) {
    if (videoSize <= 0) {
      throw ArgumentError.value(videoSize, 'videoSize', 'must be positive');
    }

    if (videoSize <= TiktokPublisher._maxChunkSize) {
      return TiktokChunkPlan(
        videoSize: videoSize,
        chunkSize: videoSize,
        totalChunkCount: 1,
      );
    }

    var chunkSize = preferredChunkSize.clamp(
      TiktokPublisher._minChunkSize,
      TiktokPublisher._maxChunkSize,
    );
    if (videoSize ~/ chunkSize < 2) {
      chunkSize = videoSize ~/ 2;
    }
    final totalChunkCount = videoSize ~/ chunkSize;

    return TiktokChunkPlan(
      videoSize: videoSize,
      chunkSize: chunkSize,
      totalChunkCount: totalChunkCount,
    );
  }
}
