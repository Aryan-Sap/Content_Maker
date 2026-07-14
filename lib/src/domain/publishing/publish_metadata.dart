/// Requested visibility for a published video.
///
/// Not every platform supports every value; publishers clamp to the nearest
/// supported option (for example TikTok maps [PublishPrivacy.unlisted] to a
/// private/self-only post).
enum PublishPrivacy { public, unlisted, private, draft }

extension PublishPrivacyDetails on PublishPrivacy {
  String get label {
    return switch (this) {
      PublishPrivacy.public => 'Public',
      PublishPrivacy.unlisted => 'Unlisted',
      PublishPrivacy.private => 'Private',
      PublishPrivacy.draft => 'Draft',
    };
  }
}

/// Caption/description and posting options shared across destinations.
class PublishMetadata {
  const PublishMetadata({
    required this.title,
    this.description = '',
    this.hashtags = const [],
    this.privacy = PublishPrivacy.private,
    this.madeForKids = false,
  });

  /// Title (YouTube) or the leading line of the caption (TikTok/Instagram).
  final String title;

  /// Long-form description or caption body.
  final String description;

  /// Hashtags without the leading `#`; publishers append them to the caption.
  final List<String> hashtags;

  /// Requested visibility.
  final PublishPrivacy privacy;

  /// YouTube requires an explicit COPPA "made for kids" self-declaration.
  final bool madeForKids;

  /// YouTube caps titles at 100 characters.
  static const int maxTitleLength = 100;

  /// Combined caption for platforms that do not separate title/description,
  /// with hashtags appended.
  String get caption {
    final buffer = StringBuffer(title.trim());
    final body = description.trim();
    if (body.isNotEmpty) {
      buffer
        ..writeln()
        ..write(body);
    }
    final tags = _formattedHashtags;
    if (tags.isNotEmpty) {
      buffer
        ..writeln()
        ..write(tags.join(' '));
    }
    return buffer.toString();
  }

  Iterable<String> get _formattedHashtags => hashtags
      .map((tag) => tag.trim().replaceAll(RegExp(r'^#+'), ''))
      .where((tag) => tag.isNotEmpty)
      .map((tag) => '#$tag');

  /// Returns a human-readable error, or null when the metadata is valid.
  String? validate() {
    if (title.trim().isEmpty) {
      return 'Add a title before publishing.';
    }
    if (title.trim().length > maxTitleLength) {
      return 'Title must be $maxTitleLength characters or fewer.';
    }
    return null;
  }

  PublishMetadata copyWith({
    String? title,
    String? description,
    List<String>? hashtags,
    PublishPrivacy? privacy,
    bool? madeForKids,
  }) {
    return PublishMetadata(
      title: title ?? this.title,
      description: description ?? this.description,
      hashtags: hashtags ?? this.hashtags,
      privacy: privacy ?? this.privacy,
      madeForKids: madeForKids ?? this.madeForKids,
    );
  }
}
