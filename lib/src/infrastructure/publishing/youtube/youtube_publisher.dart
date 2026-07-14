import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/publish_job.dart';
import '../../../domain/publishing/publish_metadata.dart';
import '../../../domain/publishing/publish_target.dart';
import '../../../domain/publishing/video_publisher.dart';

/// Publishes a rendered video to YouTube as a Short using the Data API v3
/// resumable upload protocol.
class YoutubePublisher implements VideoPublisher {
  YoutubePublisher({http.Client? client, this.chunkSize = _defaultChunkSize})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Upload chunk size in bytes. Must be a multiple of 256 KiB for the
  /// resumable protocol; 8 MiB balances throughput and progress granularity.
  final int chunkSize;

  static const int _defaultChunkSize = 8 * 1024 * 1024;

  static const String _initEndpoint =
      'https://www.googleapis.com/upload/youtube/v3/videos'
      '?uploadType=resumable&part=snippet,status';

  @override
  PublishTarget get target => PublishTarget.youtubeShort;

  /// Builds the `videos.insert` resource body. Extracted for testing.
  Map<String, dynamic> buildVideoResource(PublishMetadata metadata) {
    final tags = metadata.hashtags
        .map((tag) => tag.trim().replaceAll(RegExp(r'^#+'), ''))
        .where((tag) => tag.isNotEmpty)
        .toList();

    // "#Shorts" in the description strengthens Shorts classification for
    // vertical clips.
    final description = [
      metadata.description.trim(),
      '#Shorts',
    ].where((part) => part.isNotEmpty).join('\n\n');

    return {
      'snippet': {
        'title': metadata.title.trim(),
        'description': description,
        if (tags.isNotEmpty) 'tags': tags,
        'categoryId': '20', // Gaming
      },
      'status': {
        'privacyStatus': _privacyStatus(metadata.privacy),
        'selfDeclaredMadeForKids': metadata.madeForKids,
      },
    };
  }

  static String _privacyStatus(PublishPrivacy privacy) {
    return switch (privacy) {
      PublishPrivacy.public => 'public',
      PublishPrivacy.unlisted => 'unlisted',
      // YouTube has no draft concept; keep it private.
      PublishPrivacy.private || PublishPrivacy.draft => 'private',
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
        emit(_fail(job, 'Rendered file was not found: ${job.videoPath}'));
        return;
      }
      final totalBytes = await file.length();

      emit(
        PublishProgress(
          target: target,
          status: PublishJobStatus.uploading,
          fraction: 0,
          message: 'Starting YouTube upload.',
        ),
      );

      final uploadUrl = await _createUploadSession(
        credentials.accessToken,
        buildVideoResource(job.metadata),
        totalBytes,
      );

      final videoId = await _uploadInChunks(
        file: file,
        totalBytes: totalBytes,
        uploadUrl: uploadUrl,
        accessToken: credentials.accessToken,
        onProgress: (sent) => emit(
          PublishProgress(
            target: target,
            status: PublishJobStatus.uploading,
            fraction: totalBytes == 0 ? null : sent / totalBytes,
            message: 'Uploading to YouTube.',
          ),
        ),
      );

      emit(
        PublishProgress(
          target: target,
          status: PublishJobStatus.completed,
          fraction: 1,
          message: 'Published to YouTube.',
          postId: videoId,
          remoteUrl: 'https://youtube.com/shorts/$videoId',
        ),
      );
    } catch (error) {
      emit(_fail(job, '$error'));
    } finally {
      await controller.close();
    }
  }

  Future<String> _createUploadSession(
    String accessToken,
    Map<String, dynamic> resource,
    int totalBytes,
  ) async {
    final response = await _client.post(
      Uri.parse(_initEndpoint),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Length': '$totalBytes',
        'X-Upload-Content-Type': 'video/*',
      },
      body: jsonEncode(resource),
    );

    if (response.statusCode != 200) {
      throw Exception('YouTube upload could not start: ${response.body}');
    }
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      throw Exception('YouTube upload session did not return a URL.');
    }
    return location;
  }

  Future<String> _uploadInChunks({
    required File file,
    required int totalBytes,
    required String uploadUrl,
    required String accessToken,
    required void Function(int sent) onProgress,
  }) async {
    final handle = await file.open();
    try {
      var offset = 0;
      while (offset < totalBytes) {
        final end = (offset + chunkSize) > totalBytes
            ? totalBytes
            : offset + chunkSize;
        await handle.setPosition(offset);
        final chunk = await handle.read(end - offset);

        final response = await _client.put(
          Uri.parse(uploadUrl),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Length': '${end - offset}',
            'Content-Type': 'video/*',
            'Content-Range': 'bytes $offset-${end - 1}/$totalBytes',
          },
          body: chunk,
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final id = json['id'] as String?;
          if (id == null) {
            throw Exception('YouTube upload finished without a video id.');
          }
          onProgress(totalBytes);
          return id;
        }
        // 308 Resume Incomplete is expected between chunks.
        if (response.statusCode == 308) {
          offset = _nextOffsetFromRange(response.headers['range']) ?? end;
          onProgress(offset);
          continue;
        }
        throw Exception('YouTube upload failed: ${response.body}');
      }
      throw Exception('YouTube upload ended before completion.');
    } finally {
      await handle.close();
    }
  }

  static int? _nextOffsetFromRange(String? rangeHeader) {
    if (rangeHeader == null || rangeHeader.isEmpty) {
      return null;
    }
    final match = RegExp(r'bytes=0-(\d+)$').firstMatch(rangeHeader.trim());
    if (match == null) {
      return null;
    }
    return int.parse(match.group(1)!) + 1;
  }

  PublishProgress _fail(PublishJob job, String message) {
    return PublishProgress(
      target: target,
      status: PublishJobStatus.failed,
      message: message,
    );
  }
}
