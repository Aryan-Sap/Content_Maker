import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:content_maker/src/domain/publishing/auth/oauth_credentials.dart';
import 'package:content_maker/src/domain/publishing/publish_job.dart';
import 'package:content_maker/src/domain/publishing/publish_metadata.dart';
import 'package:content_maker/src/domain/publishing/publish_target.dart';
import 'package:content_maker/src/infrastructure/publishing/youtube/youtube_publisher.dart';

void main() {
  final publisher = YoutubePublisher();

  test('maps privacy, tags, and made-for-kids into the video resource', () {
    const metadata = PublishMetadata(
      title: 'Clutch ace',
      description: 'Ranked highlight',
      hashtags: ['#gaming', 'valorant'],
      privacy: PublishPrivacy.unlisted,
      madeForKids: true,
    );

    final resource = publisher.buildVideoResource(metadata);
    final snippet = resource['snippet'] as Map<String, dynamic>;
    final status = resource['status'] as Map<String, dynamic>;

    expect(snippet['title'], 'Clutch ace');
    expect(snippet['description'], contains('#Shorts'));
    expect(snippet['tags'], ['gaming', 'valorant']);
    expect(snippet['categoryId'], '20');
    expect(status['privacyStatus'], 'unlisted');
    expect(status['selfDeclaredMadeForKids'], isTrue);
  });

  test('draft visibility falls back to private on YouTube', () {
    const metadata = PublishMetadata(
      title: 'Clip',
      privacy: PublishPrivacy.draft,
    );

    final status =
        publisher.buildVideoResource(metadata)['status']
            as Map<String, dynamic>;

    expect(status['privacyStatus'], 'private');
  });

  test('resumes chunk upload from YouTube Range response', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'youtube-upload-test',
    );
    final file = File('${tempDir.path}${Platform.pathSeparator}clip.mp4');
    await file.writeAsBytes([1, 2, 3, 4, 5]);

    final contentRanges = <String>[];
    final contentLengths = <String>[];
    var requestCount = 0;

    final client = MockClient((request) async {
      requestCount++;
      if (request.method == 'POST') {
        return http.Response(
          '',
          200,
          headers: {'location': 'https://upload.example/session'},
        );
      }

      contentRanges.add(request.headers['Content-Range'] ?? '');
      contentLengths.add(request.headers['Content-Length'] ?? '');

      if (contentRanges.length == 1) {
        return http.Response('', 308, headers: {'range': 'bytes=0-1'});
      }

      return http.Response('{"id":"abc123"}', 201);
    });

    final publisher = YoutubePublisher(client: client, chunkSize: 3);
    final events = await publisher
        .publish(
          PublishJob(
            videoPath: file.path,
            target: PublishTarget.youtubeShort,
            metadata: const PublishMetadata(title: 'Clip'),
          ),
          const OAuthCredentials(accessToken: 'token'),
        )
        .toList();

    expect(requestCount, 3);
    expect(contentRanges, ['bytes 0-2/5', 'bytes 2-4/5']);
    expect(contentLengths, ['3', '3']);
    expect(events.last.postId, 'abc123');
    expect(events.last.remoteUrl, 'https://youtube.com/shorts/abc123');

    await tempDir.delete(recursive: true);
  });
}
