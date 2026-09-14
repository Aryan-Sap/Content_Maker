import 'dart:async';

import '../domain/publishing/auth/oauth_authenticator.dart';
import '../domain/publishing/auth/oauth_credentials.dart';
import '../domain/publishing/auth/oauth_token_store.dart';
import '../domain/publishing/publish_job.dart';
import '../domain/publishing/publish_target.dart';
import '../domain/publishing/video_publisher.dart';

/// Publishes one rendered video to one or more destinations.
///
/// For each target it validates the job, ensures a usable OAuth token
/// (refreshing or re-authorizing as needed and persisting the result), then
/// delegates to the matching [VideoPublisher]. Multiple targets are merged
/// into a single tagged [PublishProgress] stream.
class PublishExport {
  const PublishExport({
    required this.publishers,
    required this.authenticators,
    required this.tokenStore,
  });

  final Map<PublishTarget, VideoPublisher> publishers;
  final Map<PublishTarget, OAuthAuthenticator> authenticators;
  final OAuthTokenStore tokenStore;

  /// Publishes [videoPath] to each of [jobs] (one per target). Returns a merged
  /// progress stream; each event carries its `target`.
  Stream<PublishProgress> call(List<PublishJob> jobs) {
    final controller = StreamController<PublishProgress>();
    _runAll(jobs, controller);
    return controller.stream;
  }

  Future<void> _runAll(
    List<PublishJob> jobs,
    StreamController<PublishProgress> controller,
  ) async {
    try {
      await Future.wait(
        jobs.map((job) async {
          try {
            await _runOne(job, controller);
          } catch (_) {
            if (!controller.isClosed) {
              controller.add(
                PublishProgress(
                  target: job.target,
                  status: PublishJobStatus.failed,
                  message:
                      'Upload interrupted. Check your connection and retry this destination.',
                ),
              );
            }
          }
        }),
      );
    } finally {
      await controller.close();
    }
  }

  Future<void> _runOne(
    PublishJob job,
    StreamController<PublishProgress> controller,
  ) async {
    void emit(PublishProgress progress) {
      if (!controller.isClosed) {
        controller.add(progress);
      }
    }

    final publisher = publishers[job.target];
    if (publisher == null) {
      emit(
        PublishProgress(
          target: job.target,
          status: PublishJobStatus.failed,
          message: '${job.target.label} is not supported.',
        ),
      );
      return;
    }

    final validationError = job.validate();
    if (validationError != null) {
      emit(
        PublishProgress(
          target: job.target,
          status: PublishJobStatus.failed,
          message: validationError,
        ),
      );
      return;
    }

    OAuthCredentials credentials;
    try {
      credentials = await _ensureCredentials(job.target, emit);
    } on OAuthException catch (error) {
      emit(
        PublishProgress(
          target: job.target,
          status: PublishJobStatus.failed,
          message: error.message,
        ),
      );
      return;
    }

    // addStream locks a controller while it is forwarding, so concurrent
    // destinations must forward individual events instead.
    await for (final progress in publisher.publish(job, credentials)) {
      emit(progress);
    }
  }

  /// Returns valid credentials for [target], refreshing or authorizing as
  /// needed and persisting any change. Manual hand-off targets never force an
  /// interactive sign-in; they use a stored connection when one exists.
  Future<OAuthCredentials> _ensureCredentials(
    PublishTarget target,
    void Function(PublishProgress) emit,
  ) async {
    final authenticator = authenticators[target];
    if (authenticator == null) {
      return const OAuthCredentials(accessToken: '');
    }

    final stored = await tokenStore.read(target);

    if (!target.supportsAutomatedPublish) {
      if (stored == null) {
        return const OAuthCredentials(accessToken: '');
      }
      if (!stored.isExpired) {
        return stored;
      }
      if (stored.canRefresh) {
        try {
          final refreshed = await authenticator.refresh(stored);
          await tokenStore.write(target, refreshed);
          return refreshed;
        } on OAuthException {
          return const OAuthCredentials(accessToken: '');
        }
      }
      return const OAuthCredentials(accessToken: '');
    }

    if (stored != null && !stored.isExpired) {
      return stored;
    }

    if (stored != null && stored.canRefresh) {
      try {
        final refreshed = await authenticator.refresh(stored);
        await tokenStore.write(target, refreshed);
        return refreshed;
      } on OAuthException {
        // Fall through to a fresh interactive login.
      }
    }

    emit(
      PublishProgress(
        target: target,
        status: PublishJobStatus.authorizing,
        message: 'Waiting for ${target.label} sign-in in your browser.',
      ),
    );
    final fresh = await authenticator.authorize();
    await tokenStore.write(target, fresh);
    return fresh;
  }
}
