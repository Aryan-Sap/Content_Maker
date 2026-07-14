import 'dart:async';
import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../../../domain/publishing/auth/oauth_credentials.dart';
import '../../../domain/publishing/publish_job.dart';
import '../../../domain/publishing/publish_target.dart';
import '../../../domain/publishing/video_publisher.dart';

/// Instagram adapter behind the shared [VideoPublisher] contract.
///
/// Official Reels publishing (Graph API) requires a Business/Creator account
/// linked to a Facebook Page and a publicly hosted video URL. For a personal
/// account there is no compliant API, and automating the app UI would violate
/// Instagram's terms. This adapter therefore does an honest hand-off: it
/// surfaces the file for a manual upload rather than silently failing.
///
/// To enable true automation later, add an `InstagramGraphPublisher`
/// implementing [VideoPublisher] and swap it in wherever this is constructed —
/// no caller changes required.
class InstagramPublisher implements VideoPublisher {
  const InstagramPublisher();

  @override
  PublishTarget get target => PublishTarget.instagramReel;

  @override
  Stream<PublishProgress> publish(
    PublishJob job,
    OAuthCredentials credentials,
  ) async* {
    yield PublishProgress(
      target: target,
      status: PublishJobStatus.processing,
      message: 'Preparing Instagram hand-off.',
    );

    // Reveal the rendered file so the user can drag it into Instagram.
    await _revealInFileManager(job.videoPath);

    yield PublishProgress(
      target: target,
      status: PublishJobStatus.completed,
      fraction: 1,
      message:
          'Instagram Reels cannot be auto-posted from a personal account. '
          'Your rendered video is ready — upload it in the Instagram app. '
          '(Switch to a Business/Creator account to enable automated posting.)',
    );
  }

  Future<void> _revealInFileManager(String path) async {
    try {
      final directory = File(path).parent.path;
      await launchUrl(Uri.file(directory));
    } catch (_) {
      // Best-effort: the message already tells the user where the file is.
    }
  }
}
