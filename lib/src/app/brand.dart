import 'package:flutter/material.dart';

/// Content Maker brand tokens, mirroring the marketing site:
/// warm ink backgrounds, electric lime primary, vivid blue secondary,
/// cream text, Bricolage Grotesque display type over Archivo body type.
abstract final class Brand {
  // Core palette (from the landing page).
  static const ink = Color(0xFF16130D);
  static const inkDeep = Color(0xFF120F0A);
  static const lime = Color(0xFFC9F63C);
  static const blue = Color(0xFF3D53F5);
  static const blueSoft = Color(0xFF7D8DFA);
  static const cream = Color(0xFFFAF7F1);

  // Derived surfaces / lines / muted text.
  static const surface = Color(0xFF1C1812);
  static const surfaceRaised = Color(0xFF221D15);
  static const surfaceSunken = Color(0xFF191510);
  static const line = Color(0xFF39352B);
  static const lineStrong = Color(0xFF4A4537);
  static const muted = Color(0xFFB9B4A8);
  static const faint = Color(0xFF8A857A);

  static const displayFont = 'Bricolage Grotesque';
  static const bodyFont = 'Archivo';

  /// Standard corner radius for cards/panels.
  static const radius = 12.0;
  static const radiusSmall = 8.0;
}

/// The "⚡ CONTENT MAKER" wordmark used on the app bar and onboarding.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 18, this.showBolt = true});

  final double size;
  final bool showBolt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBolt) ...[
          Container(
            padding: EdgeInsets.all(size * 0.22),
            decoration: BoxDecoration(
              color: Brand.lime,
              borderRadius: BorderRadius.circular(size * 0.3),
            ),
            child: Text(
              '⚡',
              style: TextStyle(fontSize: size * 0.8, height: 1),
            ),
          ),
          SizedBox(width: size * 0.5),
        ],
        Text(
          'CONTENT MAKER',
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontWeight: FontWeight.w800,
            fontSize: size,
            letterSpacing: size * 0.06,
            color: Brand.cream,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// A rotated sticker chip like the landing page's playful badges.
class BrandSticker extends StatelessWidget {
  const BrandSticker({
    super.key,
    required this.label,
    this.rotationDegrees = -4,
    this.color = Brand.lime,
    this.textColor = Brand.ink,
  });

  final String label;
  final double rotationDegrees;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotationDegrees * 3.14159265 / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.8,
            color: textColor,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Fade + gentle upward slide entrance, optionally staggered via [delay].
/// Used to give screens and sections a smooth, branded arrival.
class BrandEntrance extends StatefulWidget {
  const BrandEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 420),
    this.offset = 24,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<BrandEntrance> createState() => _BrandEntranceState();
}

class _BrandEntranceState extends State<BrandEntrance>
    with SingleTickerProviderStateMixin {
  // The stagger delay is folded into the animation as an Interval rather than
  // scheduled with a Timer, so disposing the widget never leaves timers
  // pending (which would also trip widget tests).
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + widget.duration,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      widget.delay.inMicroseconds /
          (widget.delay + widget.duration).inMicroseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - _curve.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Smooth fade-through + slide-up route transition used app-wide.
class BrandPageTransitionsBuilder extends PageTransitionsBuilder {
  const BrandPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.15, 1, curve: Curves.easeOutCubic),
    );
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    final exitFade = Tween<double>(begin: 1, end: 0.92).animate(
      CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeIn),
    );

    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(opacity: exitFade, child: child),
      ),
    );
  }
}
