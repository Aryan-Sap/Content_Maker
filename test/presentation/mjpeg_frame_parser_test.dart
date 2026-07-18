import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/presentation/widgets/frame_stream_player.dart';

void main() {
  Uint8List jpeg(int marker) =>
      Uint8List.fromList([0xFF, 0xD8, marker, 0xFF, 0xD9]);

  test('extracts a complete frame from a single chunk', () {
    final parser = MjpegFrameParser();
    final frames = parser.feed(jpeg(0x11));

    expect(frames, hasLength(1));
    expect(frames.single, jpeg(0x11));
  });

  test('reassembles a frame split across chunks', () {
    final parser = MjpegFrameParser();

    expect(parser.feed([0xFF, 0xD8, 0x22]), isEmpty);
    final frames = parser.feed([0xFF, 0xD9]);

    expect(frames, hasLength(1));
    expect(frames.single, jpeg(0x22));
  });

  test('splits multiple frames delivered in one chunk', () {
    final parser = MjpegFrameParser();
    final frames = parser.feed([...jpeg(0x01), ...jpeg(0x02)]);

    expect(frames, hasLength(2));
    expect(frames[0], jpeg(0x01));
    expect(frames[1], jpeg(0x02));
  });

  test('discards leading garbage before the JPEG start marker', () {
    final parser = MjpegFrameParser();
    final frames = parser.feed([0x00, 0x99, ...jpeg(0x03)]);

    expect(frames, hasLength(1));
    expect(frames.single, jpeg(0x03));
  });

  test('reset clears buffered partial data', () {
    final parser = MjpegFrameParser();
    parser.feed([0xFF, 0xD8, 0x44]);
    parser.reset();
    final frames = parser.feed([0xFF, 0xD9]);

    expect(frames, isEmpty);
  });
}
