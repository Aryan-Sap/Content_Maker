import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/application/publish_export.dart';
import 'package:content_maker/src/domain/publishing/auth/oauth_authenticator.dart';
import 'package:content_maker/src/domain/publishing/auth/oauth_credentials.dart';
import 'package:content_maker/src/domain/publishing/auth/oauth_token_store.dart';
import 'package:content_maker/src/domain/publishing/publish_job.dart';
import 'package:content_maker/src/domain/publishing/publish_metadata.dart';
import 'package:content_maker/src/domain/publishing/publish_target.dart';
import 'package:content_maker/src/domain/publishing/video_publisher.dart';

class _FakeTokenStore implements OAuthTokenStore {
  _FakeTokenStore(this._value);

  OAuthCredentials? _value;
  OAuthCredentials? written;

  @override
  Future<OAuthCredentials?> read(PublishTarget target) async => _value;

  @override
  Future<void> write(PublishTarget target, OAuthCredentials credentials) async {
    written = credentials;
    _value = credentials;
  }

  @override
  Future<void> delete(PublishTarget target) async => _value = null;
}

class _FakeAuthenticator implements OAuthAuthenticator {
  bool authorizeCalled = false;
  bool refreshCalled = false;

  @override
  PublishTarget get target => PublishTarget.youtubeShort;

  @override
  Future<OAuthCredentials> authorize() async {
    authorizeCalled = true;
    return const OAuthCredentials(accessToken: 'fresh-from-authorize');
  }

  @override
  Future<OAuthCredentials> refresh(OAuthCredentials credentials) async {
    refreshCalled = true;
    return const OAuthCredentials(accessToken: 'fresh-from-refresh');
  }
}

class _RecordingPublisher implements VideoPublisher {
  OAuthCredentials? received;

  @override
  PublishTarget get target => PublishTarget.youtubeShort;

  @override
  Stream<PublishProgress> publish(
    PublishJob job,
    OAuthCredentials credentials,
  ) async* {
    received = credentials;
    yield PublishProgress(
      target: target,
      status: PublishJobStatus.completed,
      message: 'done',
    );
  }
}

class _InstagramAuthenticator extends _FakeAuthenticator {
  @override
  PublishTarget get target => PublishTarget.instagramReel;
}

class _InstagramPublisher extends _RecordingPublisher {
  @override
  PublishTarget get target => PublishTarget.instagramReel;
}

class _FailingPublisher extends _RecordingPublisher {
  @override
  Stream<PublishProgress> publish(
    PublishJob job,
    OAuthCredentials credentials,
  ) async* {
    throw StateError('private internal failure details');
  }
}

PublishJob _job() => const PublishJob(
  videoPath: 'out.mp4',
  target: PublishTarget.youtubeShort,
  metadata: PublishMetadata(title: 'Clip'),
);

PublishJob _instagramJob() => const PublishJob(
  videoPath: 'out.mp4',
  target: PublishTarget.instagramReel,
  metadata: PublishMetadata(title: 'Clip'),
);

void main() {
  test(
    'concurrent destinations both finish without locking the merged stream',
    () async {
      final useCase = PublishExport(
        publishers: {
          PublishTarget.youtubeShort: _RecordingPublisher(),
          PublishTarget.instagramReel: _InstagramPublisher(),
        },
        authenticators: {},
        tokenStore: _FakeTokenStore(null),
      );
      final progress = await useCase([_job(), _instagramJob()]).toList();
      expect(progress.where((p) => p.isSuccess).map((p) => p.target).toSet(), {
        PublishTarget.youtubeShort,
        PublishTarget.instagramReel,
      });
    },
  );

  test(
    'one provider throwing does not prevent another from completing',
    () async {
      final useCase = PublishExport(
        publishers: {
          PublishTarget.youtubeShort: _FailingPublisher(),
          PublishTarget.instagramReel: _InstagramPublisher(),
        },
        authenticators: {},
        tokenStore: _FakeTokenStore(null),
      );
      final progress = await useCase([_job(), _instagramJob()]).toList();
      expect(
        progress
            .singleWhere((p) => p.target == PublishTarget.youtubeShort)
            .status,
        PublishJobStatus.failed,
      );
      expect(
        progress
            .singleWhere((p) => p.target == PublishTarget.instagramReel)
            .isSuccess,
        isTrue,
      );
      expect(
        progress.any((p) => p.message.contains('private internal')),
        isFalse,
      );
    },
  );
  test('refreshes expired credentials and passes the new token on', () async {
    final store = _FakeTokenStore(
      OAuthCredentials(
        accessToken: 'old',
        refreshToken: 'refresh-me',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );
    final auth = _FakeAuthenticator();
    final publisher = _RecordingPublisher();

    final useCase = PublishExport(
      publishers: {PublishTarget.youtubeShort: publisher},
      authenticators: {PublishTarget.youtubeShort: auth},
      tokenStore: store,
    );

    await useCase([_job()]).toList();

    expect(auth.refreshCalled, isTrue);
    expect(auth.authorizeCalled, isFalse);
    expect(publisher.received?.accessToken, 'fresh-from-refresh');
    expect(store.written?.accessToken, 'fresh-from-refresh');
  });

  test('authorizes when there are no stored credentials', () async {
    final store = _FakeTokenStore(null);
    final auth = _FakeAuthenticator();
    final publisher = _RecordingPublisher();

    final useCase = PublishExport(
      publishers: {PublishTarget.youtubeShort: publisher},
      authenticators: {PublishTarget.youtubeShort: auth},
      tokenStore: store,
    );

    await useCase([_job()]).toList();

    expect(auth.authorizeCalled, isTrue);
    expect(publisher.received?.accessToken, 'fresh-from-authorize');
  });

  test('reuses valid stored credentials without refresh', () async {
    final store = _FakeTokenStore(
      OAuthCredentials(
        accessToken: 'still-good',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final auth = _FakeAuthenticator();
    final publisher = _RecordingPublisher();

    final useCase = PublishExport(
      publishers: {PublishTarget.youtubeShort: publisher},
      authenticators: {PublishTarget.youtubeShort: auth},
      tokenStore: store,
    );

    await useCase([_job()]).toList();

    expect(auth.refreshCalled, isFalse);
    expect(auth.authorizeCalled, isFalse);
    expect(publisher.received?.accessToken, 'still-good');
  });

  test('manual Instagram hand-off does not force sign-in', () async {
    final store = _FakeTokenStore(null);
    final auth = _InstagramAuthenticator();
    final publisher = _InstagramPublisher();

    final useCase = PublishExport(
      publishers: {PublishTarget.instagramReel: publisher},
      authenticators: {PublishTarget.instagramReel: auth},
      tokenStore: store,
    );

    await useCase([_instagramJob()]).toList();

    expect(auth.authorizeCalled, isFalse);
    expect(publisher.received?.accessToken, isEmpty);
  });
}
