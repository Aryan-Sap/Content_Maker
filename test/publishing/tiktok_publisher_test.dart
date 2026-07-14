import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:content_maker/src/domain/publishing/auth/oauth_credentials.dart';
import 'package:content_maker/src/domain/publishing/publish_job.dart';
import 'package:content_maker/src/domain/publishing/publish_metadata.dart';
import 'package:content_maker/src/domain/publishing/publish_target.dart';
import 'package:content_maker/src/infrastructure/publishing/tiktok/tiktok_publisher.dart';

void main() {
  test('public maps to PUBLIC_TO_EVERYONE when allowed', () {
    expect(
      TiktokPublisher.privacyLevel(
        PublishPrivacy.public,
        allowedLevels: const ['PUBLIC_TO_EVERYONE', 'SELF_ONLY'],
      ),
      'PUBLIC_TO_EVERYONE',
    );
  });

  test('clamps to SELF_ONLY when public is not allowed (unaudited app)', () {
    expect(
      TiktokPublisher.privacyLevel(
        PublishPrivacy.public,
        allowedLevels: const ['SELF_ONLY'],
      ),
      'SELF_ONLY',
    );
  });

  test('private always maps to SELF_ONLY', () {
    expect(TiktokPublisher.privacyLevel(PublishPrivacy.private), 'SELF_ONLY');
  });

  test('init request carries the chunk plan and caption', () {
    const metadata = PublishMetadata(
      title: 'Clutch ace',
      hashtags: ['gaming'],
      privacy: PublishPrivacy.private,
    );

    final request = TiktokPublisher().buildInitRequest(
      metadata: metadata,
      videoSize: 1000,
      chunkSize: 1000,
      totalChunkCount: 1,
    );

    final postInfo = request['post_info'] as Map<String, dynamic>;
    final sourceInfo = request['source_info'] as Map<String, dynamic>;

    expect(postInfo['privacy_level'], 'SELF_ONLY');
    expect(postInfo['title'], contains('Clutch ace'));
    expect(sourceInfo['source'], 'FILE_UPLOAD');
    expect(sourceInfo['video_size'], 1000);
    expect(sourceInfo['total_chunk_count'], 1);
    expect(postInfo['brand_content_toggle'], isFalse);
    expect(postInfo['brand_organic_toggle'], isFalse);
  });

  test('uses whole upload for videos up to TikTok single-chunk limit', () {
    const videoSize = 50 * 1024 * 1024;

    final plan = TiktokChunkPlan.forVideo(
      videoSize: videoSize,
      preferredChunkSize: 32 * 1024 * 1024,
    );

    expect(plan.chunkSize, videoSize);
    expect(plan.totalChunkCount, 1);
  });

  test('merges trailing bytes into final TikTok chunk', () {
    const videoSize = 70 * 1000 * 1000 + 123;

    final plan = TiktokChunkPlan.forVideo(
      videoSize: videoSize,
      preferredChunkSize: 10 * 1000 * 1000,
    );

    expect(plan.chunkSize, 10 * 1000 * 1000);
    expect(plan.totalChunkCount, 7);
  });

  test('publishes video through TikTok init upload and status flow', () async {
    final tempDir = await Directory.systemTemp.createTemp('tiktok-upload-test');
    final file = File('${tempDir.path}${Platform.pathSeparator}clip.mp4');
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    final seenMethods = <String>[];
    final seenUploadRanges = <String>[];
    final client = MockClient((request) async {
      seenMethods.add('${request.method} ${request.url.path}');

      if (request.url.path.endsWith('/creator_info/query/')) {
        return http.Response(
          jsonEncode({
            'data': {
              'privacy_level_options': ['SELF_ONLY'],
            },
            'error': {'code': 'ok', 'message': ''},
          }),
          200,
        );
      }

      if (request.url.path.endsWith('/video/init/')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final postInfo = body['post_info'] as Map<String, dynamic>;
        final sourceInfo = body['source_info'] as Map<String, dynamic>;

        expect(postInfo['privacy_level'], 'SELF_ONLY');
        expect(sourceInfo['video_size'], 5);
        expect(sourceInfo['chunk_size'], 5);
        expect(sourceInfo['total_chunk_count'], 1);

        return http.Response(
          jsonEncode({
            'data': {
              'publish_id': 'publish-123',
              'upload_url': 'https://upload.example/tiktok',
            },
            'error': {'code': 'ok', 'message': ''},
          }),
          200,
        );
      }

      if (request.method == 'PUT' && request.url.host == 'upload.example') {
        seenUploadRanges.add(request.headers['Content-Range'] ?? '');
        expect(request.headers['Content-Length'], '5');
        return http.Response('', 200);
      }

      if (request.url.path.endsWith('/status/fetch/')) {
        return http.Response(
          jsonEncode({
            'data': {
              'status': 'PUBLISH_COMPLETE',
              'publicaly_available_post_id': ['post-123'],
            },
            'error': {'code': 'ok', 'message': ''},
          }),
          200,
        );
      }

      return http.Response('unexpected request', 500);
    });

    final publisher = TiktokPublisher(
      client: client,
      pollInterval: Duration.zero,
    );
    final events = await publisher
        .publish(
          PublishJob(
            videoPath: file.path,
            target: PublishTarget.tiktok,
            metadata: const PublishMetadata(
              title: 'Clip',
              privacy: PublishPrivacy.public,
            ),
          ),
          const OAuthCredentials(accessToken: 'token'),
        )
        .toList();

    expect(seenMethods, [
      'POST /v2/post/publish/creator_info/query/',
      'POST /v2/post/publish/video/init/',
      'PUT /tiktok',
      'POST /v2/post/publish/status/fetch/',
    ]);
    expect(seenUploadRanges, ['bytes 0-4/5']);
    expect(events.last.status, PublishJobStatus.completed);
    expect(events.last.postId, 'post-123');

    await tempDir.delete(recursive: true);
  });
}
