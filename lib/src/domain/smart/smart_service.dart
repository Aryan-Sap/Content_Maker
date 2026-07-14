class SmartServiceUnavailable implements Exception {
  const SmartServiceUnavailable([this.message = 'Smart service unavailable.']);

  final String message;

  @override
  String toString() => message;
}

class CaptionSegment {
  const CaptionSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });

  final double startSeconds;
  final double endSeconds;
  final String text;
}

abstract interface class SmartService {
  bool get isAvailable;

  Future<List<CaptionSegment>> createCaptions(String mediaPath);

  Future<String> removeBackground(String mediaPath);

  Future<String> autoReframe(String mediaPath, {required double aspectRatio});
}

class UnavailableSmartService implements SmartService {
  const UnavailableSmartService();

  @override
  bool get isAvailable => false;

  @override
  Future<List<CaptionSegment>> createCaptions(String mediaPath) {
    throw const SmartServiceUnavailable();
  }

  @override
  Future<String> removeBackground(String mediaPath) {
    throw const SmartServiceUnavailable();
  }

  @override
  Future<String> autoReframe(String mediaPath, {required double aspectRatio}) {
    throw const SmartServiceUnavailable();
  }
}
