import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/brand.dart';

class GuidedTourOverlay extends StatefulWidget {
  const GuidedTourOverlay({
    super.key,
    required this.targetKey,
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.description,
    required this.onSkip,
    this.accent = Brand.lime,
    this.actionLabel,
    this.onAction,
    this.actionEnabled = true,
    this.onNext,
    this.nextLabel = 'Next',
  });

  final GlobalKey targetKey;
  final int step;
  final int totalSteps;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onSkip;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionEnabled;
  final VoidCallback? onNext;
  final String nextLabel;

  @override
  State<GuidedTourOverlay> createState() => _GuidedTourOverlayState();
}

class _GuidedTourOverlayState extends State<GuidedTourOverlay> {
  Rect? _targetRect;

  @override
  void initState() {
    super.initState();
    _measureTarget();
  }

  @override
  void didUpdateWidget(covariant GuidedTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _measureTarget();
  }

  void _measureTarget() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetBox =
          widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
      final overlayBox = context.findRenderObject() as RenderBox?;
      if (targetBox == null ||
          overlayBox == null ||
          !targetBox.hasSize ||
          !overlayBox.hasSize) {
        Future<void>.delayed(const Duration(milliseconds: 80), _measureTarget);
        return;
      }
      final topLeft = targetBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      final nextRect = (topLeft & targetBox.size).inflate(8);
      if (_targetRect != nextRect) {
        setState(() => _targetRect = nextRect);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounds = Offset.zero & constraints.biggest;
        final target =
            (_targetRect ??
                    Rect.fromCenter(
                      center: bounds.center,
                      width: 160,
                      height: 64,
                    ))
                .intersect(bounds);
        final cardWidth = math.min(410.0, constraints.maxWidth - 32);
        final placeBelow = constraints.maxHeight - target.bottom >= 230;
        final cardTop = placeBelow
            ? math.min(target.bottom + 18, constraints.maxHeight - 210)
            : math.max(16.0, target.top - 210);
        final cardLeft = math.max(
          16.0,
          math.min(
            target.center.dx - cardWidth / 2,
            constraints.maxWidth - cardWidth - 16,
          ),
        );

        return Stack(
          children: [
            _Blocker(rect: Rect.fromLTRB(0, 0, bounds.width, target.top)),
            _Blocker(
              rect: Rect.fromLTRB(0, target.top, target.left, target.bottom),
            ),
            _Blocker(
              rect: Rect.fromLTRB(
                target.right,
                target.top,
                bounds.width,
                target.bottom,
              ),
            ),
            _Blocker(
              rect: Rect.fromLTRB(
                0,
                target.bottom,
                bounds.width,
                bounds.height,
              ),
            ),
            Positioned.fromRect(
              rect: target,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: widget.accent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.2),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: cardLeft,
              top: cardTop,
              width: cardWidth,
              child: _CoachCard(
                step: widget.step,
                totalSteps: widget.totalSteps,
                title: widget.title,
                description: widget.description,
                accent: widget.accent,
                onSkip: widget.onSkip,
                actionLabel: widget.actionLabel,
                onAction: widget.onAction,
                actionEnabled: widget.actionEnabled,
                onNext: widget.onNext,
                nextLabel: widget.nextLabel,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Blocker extends StatelessWidget {
  const _Blocker({required this.rect});

  final Rect rect;

  @override
  Widget build(BuildContext context) {
    if (rect.width <= 0 || rect.height <= 0) return const SizedBox.shrink();
    return Positioned.fromRect(
      rect: rect,
      child: ColoredBox(color: Brand.scrim),
    );
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.description,
    required this.accent,
    required this.onSkip,
    required this.actionLabel,
    required this.onAction,
    required this.actionEnabled,
    required this.onNext,
    required this.nextLabel,
  });

  final int step;
  final int totalSteps;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onSkip;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionEnabled;
  final VoidCallback? onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      elevation: 18,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'STEP $step OF $totalSteps',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Brand.ink,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(onPressed: onSkip, child: const Text('Skip tour')),
              ],
            ),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 7),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Brand.muted,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            if (actionLabel != null)
              FilledButton.icon(
                onPressed: actionEnabled ? onAction : null,
                icon: const Icon(Icons.arrow_forward),
                label: Text(actionLabel!),
              )
            else if (onNext != null)
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.arrow_forward),
                label: Text(nextLabel),
              )
            else
              Row(
                children: [
                  Icon(Icons.touch_app_outlined, color: accent, size: 19),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Use the highlighted control to continue.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
