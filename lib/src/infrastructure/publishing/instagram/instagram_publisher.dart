import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
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
/// Instagram's terms. This adapter therefore performs the smoothest compliant
/// hand-off possible:
///
/// 1. Copies the finished caption (title + hashtags) to the clipboard.
/// 2. Reveals the rendered file in the file manager (selected, on Windows).
/// 3. Opens Instagram's web uploader in the browser.
///
/// The user drags the file in and pastes the caption — two gestures.
///
/// To enable true automation later, add an `InstagramGraphPublisher`
/// implementing [VideoPublisher] and swap it in wherever this is constructed —
/// no caller changes required.
class InstagramPublisher implements VideoPublisher {
  const InstagramPublisher();

  static final Uri _webUploadUri = Uri.parse(
    'https://www.instagram.com/reels/create/',
  );

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
      fraction: 0.2,
      message: 'Copying your caption to the clipboard…',
    );
    final caption = job.metadata.caption;
    var captionCopied = false;
    try {
      await Clipboard.setData(ClipboardData(text: caption));
      captionCopied = caption.trim().isNotEmpty;
    } catch (_) {
      // Clipboard is a convenience; the hand-off still works without it.
    }

    yield PublishProgress(
      target: target,
      status: PublishJobStatus.processing,
      fraction: 0.5,
      message: 'Showing the rendered file…',
    );
    await _revealInFileManager(job.videoPath);

    yield PublishProgress(
      target: target,
      status: PublishJobStatus.processing,
      fraction: 0.8,
      message: 'Opening Instagram…',
    );
    await _openInstagram();

    yield PublishProgress(
      target: target,
      status: PublishJobStatus.completed,
      fraction: 1,
      message: captionCopied
          ? 'Ready to post: drag the selected file into Instagram and paste '
                'the caption (already on your clipboard). Personal accounts '
                'cannot be auto-posted via the official API.'
          : 'Ready to post: drag the selected file into the Instagram '
                'uploader. Personal accounts cannot be auto-posted via the '
                'official API.',
    );
  }

  Future<void> _revealInFileManager(String path) async {
    try {
      if (Platform.isWindows) {
        // Opens Explorer with the rendered file pre-selected.
        await Process.run('explorer.exe', ['/select,$path']);
        return;
      }
      await launchUrl(Uri.file(File(path).parent.path));
    } catch (_) {
      // Best-effort: the completion message tells the user where the file is.
    }
  }

  Future<void> _openInstagram() async {
    try {
      await launchUrl(_webUploadUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Best-effort; the user can open Instagram manually.
    }
  }
}
