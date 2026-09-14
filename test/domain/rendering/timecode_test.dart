import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/rendering/timecode.dart';

void main() {
  group('trim timecodes', () {
    test('parses minute-second values', () {
      expect(parseTrimTimecode('1:30'), 90);
      expect(parseTrimTimecode('0:05.5'), 5.5);
      expect(parseTrimTimecode('12:03'), 723);
    });

    test('accepts legacy raw-second values', () {
      expect(parseTrimTimecode('90'), 90);
      expect(parseTrimTimecode('2.5'), 2.5);
    });

    test('rejects invalid timecodes', () {
      expect(parseTrimTimecode('1:60'), isNull);
      expect(parseTrimTimecode('-1:30'), isNull);
      expect(parseTrimTimecode('hello'), isNull);
    });

    test('formats seconds as minute-second values', () {
      expect(formatTrimTimecode(90), '1:30');
      expect(formatTrimTimecode(5), '0:05');
      expect(formatTrimTimecode(5.25), '0:05.25');
    });
  });
}
