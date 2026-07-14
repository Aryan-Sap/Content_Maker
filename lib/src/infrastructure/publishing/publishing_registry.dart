import '../../domain/publishing/auth/oauth_authenticator.dart';
import '../../domain/publishing/auth/oauth_token_store.dart';
import '../../domain/publishing/publish_target.dart';
import '../../domain/publishing/video_publisher.dart';
import 'instagram/instagram_publisher.dart';
import 'oauth/oauth_config.dart';
import 'oauth/secure_oauth_token_store.dart';
import 'tiktok/tiktok_oauth_authenticator.dart';
import 'tiktok/tiktok_publisher.dart';
import 'youtube/youtube_oauth_authenticator.dart';
import 'youtube/youtube_publisher.dart';

/// Composition root for the publishing feature: builds the default set of
/// platform publishers, authenticators, and the secure token store. Swap
/// individual entries here (for example a future `InstagramGraphPublisher`)
/// without touching the application or presentation layers.
class PublishingRegistry {
  PublishingRegistry({
    OAuthTokenStore? tokenStore,
    Map<PublishTarget, VideoPublisher>? publishers,
    Map<PublishTarget, OAuthAuthenticator>? authenticators,
  }) : tokenStore = tokenStore ?? const SecureOAuthTokenStore(),
       publishers = publishers ?? _defaultPublishers(),
       authenticators = authenticators ?? _defaultAuthenticators();

  final OAuthTokenStore tokenStore;
  final Map<PublishTarget, VideoPublisher> publishers;

  /// Targets without an authenticator (Instagram) publish without OAuth.
  final Map<PublishTarget, OAuthAuthenticator> authenticators;

  static Map<PublishTarget, VideoPublisher> _defaultPublishers() {
    return {
      PublishTarget.youtubeShort: YoutubePublisher(),
      PublishTarget.tiktok: TiktokPublisher(),
      PublishTarget.instagramReel: const InstagramPublisher(),
    };
  }

  static Map<PublishTarget, OAuthAuthenticator> _defaultAuthenticators() {
    return {
      PublishTarget.youtubeShort: YoutubeOAuthAuthenticator(
        config: OAuthConfig.resolveForTarget(PublishTarget.youtubeShort)!,
      ),
      PublishTarget.tiktok: TiktokOAuthAuthenticator(
        config: OAuthConfig.resolveForTarget(PublishTarget.tiktok)!,
      ),
    };
  }
}
