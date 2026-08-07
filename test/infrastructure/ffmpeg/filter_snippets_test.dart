import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:content_maker/src/domain/editing/timeline_clip.dart';
import 'package:content_maker/src/infrastructure/ffmpeg/filter_snippets.dart';

void main() {
  test('builds grade and look snippets', () {
    const grade = ColorGrade(
      saturation: 1.25,
      brightness: -0.05,
      contrast: 1.1,
      gamma: 0.95,
      temperature: 0.5,
      tint: -0.4,
      highlights: 0.2,
      shadows: -0.2,
      fade: 0.1,
      vignette: 0.35,
      lutId: 'cinematic',
      lutIntensity: 0.75,
    );

    expect(
      FilterSnippets.grade(grade),
      'eq=brightness=-0.05:saturation=1.25:contrast=1.1:gamma=0.95',
    );
    expect(
      FilterSnippets.look(grade),
      containsAll([
        'colortemperature=temperature=8250',
        'colorbalance=gm=0.1',
        "curves=all='0/0.1 0.25/0.264 0.75/0.786 1/1'",
        'vignette=angle=0.62',
      ]),
    );
    expect(
      FilterSnippets.lut(grade, 'assets/luts'),
      "lut3d='assets/luts/cinematic.cube'",
    );
  });

  test('builds speed, reverse, and audio fade snippets', () {
    const motion = ClipMotion(speed: 0.25, reverse: true);
    const audio = ClipAudio(fadeInSeconds: 0.5, fadeOutSeconds: 1);

    expect(FilterSnippets.reverse(motion), 'reverse');
    expect(FilterSnippets.speed(motion), 'setpts=PTS/0.25');
    expect(FilterSnippets.audioTempo(0.25), ['atempo=0.5', 'atempo=0.5']);
    expect(FilterSnippets.afade(audio, 5), [
      'afade=t=in:st=0:d=0.5',
      'afade=t=out:st=4:d=1',
    ]);
  });

  test('builds a timed text overlay with an editable fade-out', () {
    const text = TextSpec(
      content: "We're live: now",
      font: 'Arial',
      size: 72,
      colorHex: 'C9F63C',
      x: 120,
      y: -240,
      fadeOutSeconds: 0.75,
    );

    final filter = FilterSnippets.drawText(
      text,
      startSeconds: 2,
      endSeconds: 6,
    );

    expect(filter, contains("text='We\\'re live\\: now'"));
    expect(
      filter,
      contains(Platform.isWindows ? "fontfile='" : "font='Arial'"),
    );
    expect(filter, contains('fontsize=72:fontcolor=0xC9F63C'));
    expect(filter, contains('x=(w-text_w)/2+120'));
    expect(filter, contains('y=(h-text_h)/2+-240'));
    expect(filter, contains("alpha='min(1\\,max(0\\,(6-t)/0.75))'"));
    expect(filter, contains("enable='between(t,2,6)'"));
  });
}
