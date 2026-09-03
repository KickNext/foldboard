import 'package:flutter/material.dart';

import '../../../../core/app_theme.dart';

/// Carries the painted hover pose across the outgoing scene's remount.
/// A frozen scene must not react to pointer exits caused by IgnorePointer.
class ReferenceHoverScene extends InheritedWidget {
  const ReferenceHoverScene({
    super.key,
    required this.values,
    this.frozen = false,
    required super.child,
  });

  final Map<Key, double> values;
  final bool frozen;

  @override
  bool updateShouldNotify(ReferenceHoverScene oldWidget) =>
      values != oldWidget.values || frozen != oldWidget.frozen;
}

/// The counterpart of the inward process mirror: reflections open outwards.
/// Only the decoration moves; hit bounds, text and edge anchors stay fixed.
class ReferencePortal extends StatefulWidget {
  const ReferencePortal({super.key, required this.child});
  final Widget child;

  @override
  State<ReferencePortal> createState() => _ReferencePortalState();
}

class _ReferencePortalState extends State<ReferencePortal> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scene = context
        .dependOnInheritedWidgetOfExactType<ReferenceHoverScene>();
    if (scene?.frozen == true) {
      return _reflections(
        context,
        scene!.values[widget.key] ?? 0,
        widget.child,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _hovered ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppTheme.portalHover,
        curve: AppTheme.portalHoverCurve,
        child: widget.child,
        builder: (context, openness, child) {
          if (widget.key case final key?) scene?.values[key] = openness;
          return _reflections(context, openness, child!);
        },
      ),
    );
  }

  Widget _reflections(BuildContext context, double openness, Widget child) =>
      Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -AppTheme.referencePortalExtent,
            top: -AppTheme.referencePortalExtent,
            right: -AppTheme.referencePortalExtent,
            bottom: -AppTheme.referencePortalExtent,
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: ReferencePortalPainter(context.colors, openness),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      );
}

class ReferencePortalPainter extends CustomPainter {
  const ReferencePortalPainter(this.palette, this.openness);
  final AppPalette palette;
  final double openness;

  /// Parallel rounded contours: radius grows by exactly the outward gap.
  static List<RRect> reflections(Size cardSize, double openness) {
    final t = openness.clamp(0.0, 1.0);
    final card = RRect.fromRectAndRadius(
      Offset.zero & cardSize,
      const Radius.circular(AppTheme.radiusCard),
    );
    return List.generate(3, (i) {
      final gap = (i + 1) * (2.5 + 3.5 * t);
      return card.inflate(gap);
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    const extent = AppTheme.referencePortalExtent;
    final cardSize = Size(size.width - extent * 2, size.height - extent * 2);
    if (cardSize.isEmpty) return;
    final card = const Offset(extent, extent) & cardSize;
    final frames = reflections(cardSize, openness);
    for (var i = frames.length - 1; i >= 0; i--) {
      final frame = frames[i].shift(const Offset(extent, extent));
      final alpha = (.42 + .38 * openness) * [1.0, .58, .28][i];
      // A subtle transparent pane between each reflection, not a solid badge.
      canvas.drawRRect(
        frame,
        Paint()
          ..color = palette.accent.withValues(alpha: .012 + .008 * openness),
      );
      canvas.drawRRect(
        frame,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.accent.withValues(alpha: alpha),
              palette.accent.withValues(alpha: alpha * .22),
              palette.accent.withValues(alpha: alpha * .8),
            ],
            stops: const [0, .5, 1],
          ).createShader(card.inflate(extent))
          ..style = PaintingStyle.stroke
          ..strokeWidth = .85,
      );
    }
  }

  @override
  bool shouldRepaint(ReferencePortalPainter oldDelegate) =>
      palette != oldDelegate.palette || openness != oldDelegate.openness;
}
