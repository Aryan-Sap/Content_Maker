import 'package:flutter/material.dart';
import '../../../theme/studio_theme.dart';

/// A graphic viewfinder, not a thumbnail or fabricated project preview.
class StudioSignature extends StatelessWidget {
  const StudioSignature({super.key});
  @override
  Widget build(BuildContext context) {
    final c = StudioTheme.of(context);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 2.6,
        child: CustomPaint(painter: _FrameStudy(c)),
      ),
    );
  }
}

class _FrameStudy extends CustomPainter {
  _FrameStudy(this.colors);
  final StudioTheme colors;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, paint..color = colors.inset);
    final frame = Rect.fromLTWH(w * .06, h * .15, w * .73, h * .7);
    canvas.drawRect(frame, paint..color = colors.selection);
    canvas.save();
    canvas.clipRect(frame);
    canvas.drawCircle(
      Offset(w * .61, h * .36),
      h * .18,
      paint..color = colors.accent,
    );
    final hill = Path()
      ..moveTo(0, h)
      ..lineTo(w * .35, h * .34)
      ..lineTo(w * .6, h * .79)
      ..lineTo(w * .82, h * .53)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hill, paint..color = colors.ink);
    canvas.restore();
    paint
      ..color = colors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(w * .44, h * .07, w * .22, h * .86), paint);
    paint.style = PaintingStyle.fill;
    for (var i = 0; i < 13; i++) {
      final x = w * .06 + i * w * .061;
      canvas.drawRect(
        Rect.fromLTWH(x, h * .96, 1, i % 3 == 0 ? h * .04 : h * .02),
        paint,
      );
    }
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(w * .85, h * .18 + i * h * .135, w * .07, h * .075),
        paint..color = i == 2 ? colors.accent : colors.line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FrameStudy oldDelegate) =>
      oldDelegate.colors != colors;
}
