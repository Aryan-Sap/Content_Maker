import 'package:content_maker/src/infrastructure/ffmpeg/mobile_ffmpeg_arguments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile arguments preserve the complete desktop render graph', () {
    final adapted = MobileFfmpegArguments.adapt(const [
      '-filter_complex',
      '[0:v]scale=1080:1920,eq=contrast=1.2:saturation=1.1,'
          'unsharp=5:5:0.5[v]',
      '-c:v',
      'libx264',
      '-preset',
      'medium',
      '-crf',
      '16',
      '-r',
      '60',
      'output.mp4',
    ]);

    expect(adapted, containsAllInOrder(['-c:v', 'libx264']));
    final graph = adapted[adapted.indexOf('-filter_complex') + 1];
    expect(graph, contains('eq=contrast=1.2:saturation=1.1'));
    expect(graph, contains('unsharp=5:5:0.5'));
    expect(adapted, containsAllInOrder(['-r', '60', 'output.mp4']));
    expect(adapted, containsAllInOrder(['-preset', 'medium']));
    expect(adapted, containsAllInOrder(['-crf', '16']));
  });
}
