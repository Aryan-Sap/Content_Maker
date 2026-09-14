/// Parses an Auto Edit trim timecode into seconds.
///
/// The preferred format is `m:ss` (optionally with decimal seconds). Plain
/// numeric values are still accepted so existing workflows that entered raw
/// seconds continue to work.
double? parseTrimTimecode(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return null;
  }

  if (!text.contains(':')) {
    final seconds = double.tryParse(text);
    return seconds != null && seconds >= 0 ? seconds : null;
  }

  final match = RegExp(r'^(\d+):([0-5]?\d(?:\.\d+)?)$').firstMatch(text);
  if (match == null) {
    return null;
  }

  final minutes = int.parse(match.group(1)!);
  final seconds = double.parse(match.group(2)!);
  if (seconds >= 60) {
    return null;
  }
  return (minutes * 60) + seconds;
}

/// Formats seconds as an Auto Edit `m:ss` timecode.
String formatTrimTimecode(double seconds) {
  final safeSeconds = seconds.isFinite && seconds > 0 ? seconds : 0.0;
  final minutes = safeSeconds ~/ 60;
  final remaining = safeSeconds - (minutes * 60);
  final wholeSeconds = remaining.floor();
  final fraction = remaining - wholeSeconds;

  if (fraction.abs() < 0.0005) {
    return '$minutes:${wholeSeconds.toString().padLeft(2, '0')}';
  }

  final fractionText = fraction
      .toStringAsFixed(3)
      .substring(1)
      .replaceFirst(RegExp(r'0+$'), '');
  return '$minutes:${wholeSeconds.toString().padLeft(2, '0')}$fractionText';
}
