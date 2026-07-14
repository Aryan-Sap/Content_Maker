class MediaMetadata {
  const MediaMetadata({
    required this.path,
    this.durationSeconds,
    this.frameRate,
    this.width,
    this.height,
    this.sampleAspectRatio,
    required this.hasAudio,
  });

  final String path;
  final double? durationSeconds;
  final double? frameRate;
  final int? width;
  final int? height;
  final String? sampleAspectRatio;
  final bool hasAudio;
}

abstract interface class MediaProbe {
  Future<MediaMetadata> probe(String path);
}
