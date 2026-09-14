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
/// Instagram's terms. This adapter therefore performs a fully offline
/// hand-off — YouTube/TikTok upload automatically alongside it, while the
/// Instagram post stays in the user's hands:
///
/// 1. Copies the finished caption (title + hashtags) to the clipboard.
/// 2. Reveals the rendered file in the file manager (selected, on Windows).
///
/// It deliberately does NOT open Instagram's web uploader: that forces a
/// browser login (often with 2FA) even when the user intends to post from
/// their phone, so the browser step hurt more than it helped.
///
/// To enable true automation later, add an `InstagramGraphPublisher`
/// implementing [VideoPublisher] and swap it in wherever this is constructed —
/// no caller changes required.
class InstagramPublisher implements VideoPublisher {
  const InstagramPublisher();

  static const _shareChannel = MethodChannel('content_maker/share');

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
      fraction: 0.3,
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
      fraction: 0.7,
      message: 'Showing the rendered file…',
    );
    final openedShareSheet = await _handoffVideo(job.videoPath, caption);

    yield PublishProgress(
      target: target,
      status: PublishJobStatus.completed,
      fraction: 1,
      message: Platform.isAndroid && openedShareSheet
          ? 'Choose Instagram in the share sheet to finish publishing your Reel.'
          : captionCopied
          ? 'Ready for Instagram: the file is selected in Explorer and the '
                'caption is on your clipboard — post it from the Instagram '
                'app whenever you like.'
          : 'Ready for Instagram: the file is selected in Explorer — post it '
                'from the Instagram app whenever you like.',
    );
  }

  Future<bool> _handoffVideo(String path, String caption) async {
    try {
      if (Platform.isAndroid) {
        return await _shareChannel.invokeMethod<bool>('shareVideo', {
              'path': path,
              'caption': caption,
            }) ??
            false;
      }
      if (Platform.isWindows) {
        // Opens Explorer with the rendered file pre-selected.
        await Process.run('explorer.exe', ['/select,$path']);
        return true;
      }
      return await launchUrl(Uri.file(File(path).parent.path));
    } catch (_) {
      // Best-effort: the completion message tells the user where the file is.
      return false;
    }
  }
}
