/// The social destinations a rendered short can be published to.
enum PublishTarget { youtubeShort, tiktok, instagramReel }

extension PublishTargetDetails on PublishTarget {
  /// Human-readable name shown in the UI.
  String get label {
    return switch (this) {
      PublishTarget.youtubeShort => 'YouTube Short',
      PublishTarget.tiktok => 'TikTok',
      PublishTarget.instagramReel => 'Instagram Reel',
    };
  }

  /// Stable key used for token storage and analytics.
  String get storageKey {
    return switch (this) {
      PublishTarget.youtubeShort => 'youtube',
      PublishTarget.tiktok => 'tiktok',
      PublishTarget.instagramReel => 'instagram',
    };
  }

  /// Whether the platform exposes an official API that uploads the video
  /// binary directly and posts it without a manual step.
  bool get supportsDirectPost {
    return switch (this) {
      PublishTarget.youtubeShort => true,
      PublishTarget.tiktok => true,
      PublishTarget.instagramReel => false,
    };
  }

  /// Whether publishing requires the video to be reachable at a public URL
  /// (Instagram Graph API) instead of a direct binary upload.
  bool get requiresPublicUrl {
    return switch (this) {
      PublishTarget.youtubeShort => false,
      PublishTarget.tiktok => false,
      PublishTarget.instagramReel => true,
    };
  }

  /// Whether the platform can be fully automated for the accounts this app
  /// currently supports. Instagram is hand-off only for personal accounts.
  bool get supportsAutomatedPublish => supportsDirectPost;
}
