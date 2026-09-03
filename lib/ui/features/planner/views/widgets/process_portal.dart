import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/app_theme.dart';

/// A finite hover animation: mirrors do not keep a ticker running while idle.
class ProcessPortal extends StatefulWidget {
  const ProcessPortal({super.key, required this.child});
  final Widget child;
  @override
  State<ProcessPortal> createState() => _ProcessPortalState();
}

class _ProcessPortalState extends State<ProcessPortal> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: _hovered ? 1 : 0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.portalHover,
      curve: AppTheme.portalHoverCurve,
      child: widget.child,
      builder: (context, depth, child) => RepaintBoundary(
        child: CustomPaint(
          painter: InfinityMirrorPainter(context.colors, depth),
          child: child,
        ),
      ),
    ),
  );
}

/// Full-card reflections: centered at rest, with perspective only on hover.
class InfinityMirrorPainter extends CustomPainter {
  InfinityMirrorPainter(this.palette, this.depth);
  final AppPalette palette;
  final double depth;

  static Rect window(Size size) {
    return (Offset.zero & size).deflate(
      math.min(AppTheme.mirrorInset, size.shortestSide / 2),
    );
  }

  static List<RRect> reflections(Size size, double depth) {
    final well = window(size);
    final outerRadius = math.min(
      AppTheme.radiusProcessCard,
      size.shortestSide / 2,
    );
    const count = 8;
    const skew = .2;
    final availableRadius = math.max(0.0, outerRadius - well.left);
    // This rounded reference defines the corner shapes, not the hover motion.
    // Keep the established depth/vanishing-point animation independent of it.
    final spacing =
        math.max(0.0, availableRadius - AppTheme.mirrorMinRadius) /
        ((count - 1) * (1 + skew));
    final t = depth.clamp(0.0, 1.0);
    return List.generate(count, (i) {
      final inset = spacing * i;
      final referenceRect = well.deflate(inset).shift(Offset(inset * skew, 0));
      final left = math.max(0.0, outerRadius - referenceRect.left);
      final right = math.max(
        0.0,
        outerRadius - (size.width - referenceRect.right),
      );
      final top = math.max(0.0, outerRadius - referenceRect.top);
      final bottom = math.max(
        0.0,
        outerRadius - (size.height - referenceRect.bottom),
      );
      final reference = RRect.fromRectAndCorners(
        referenceRect,
        topLeft: Radius.elliptical(left, top),
        topRight: Radius.elliptical(right, top),
        bottomLeft: Radius.elliptical(left, bottom),
        bottomRight: Radius.elliptical(right, bottom),
      );
      if (i == 0) return reference;
      // Restore the original small rightward perspective shift. Never expand
      // the rings toward the reference rectangle on hover.
      final scale = math.pow(.78 - .015 * t, i).toDouble();
      final vanishing = well.center + Offset(well.width * .3 * t, 0);
      final frameRect = Rect.fromCenter(
        center: Offset.lerp(vanishing, well.center, scale)!,
        width: well.width * scale,
        height: well.height * scale,
      );
      Radius project(Radius radius) => Radius.elliptical(
        referenceRect.width == 0
            ? 0
            : radius.x * frameRect.width / referenceRect.width,
        referenceRect.height == 0
            ? 0
            : radius.y * frameRect.height / referenceRect.height,
      );
      final frame = RRect.fromRectAndCorners(
        frameRect,
        topLeft: project(reference.tlRadius),
        topRight: project(reference.trRadius),
        bottomLeft: project(reference.blRadius),
        bottomRight: project(reference.brRadius),
      );
      return frame;
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppTheme.radiusProcessCard),
    );
    canvas.drawRRect(shape, Paint()..color = palette.surface);
    final well = window(size);
    final rings = reflections(size, depth);
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.alphaBlend(
              palette.accent.withValues(alpha: .16),
              palette.background,
            ),
            palette.surface,
          ],
        ).createShader(well),
    );
    for (var i = rings.length - 1; i >= 0; i--) {
      final alpha = (.6 + .25 * depth) * math.pow(.76, i);
      canvas.drawRRect(
        rings[i],
        Paint()
          ..color = palette.accent.withValues(alpha: alpha * .1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawRRect(
        rings[i],
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.accent.withValues(alpha: alpha),
              palette.accent.withValues(alpha: alpha * .3),
              palette.accent.withValues(alpha: alpha * .75),
            ],
            stops: const [0, .5, 1],
          ).createShader(well)
          ..style = PaintingStyle.stroke
          ..strokeWidth = .85,
      );
    }
    // Restore the original text veil, without a separate icon or narrow column.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.surface,
            palette.surface.withValues(alpha: .94),
            palette.surface.withValues(alpha: .15),
          ],
          stops: const [0, .46, 1],
        ).createShader(Offset.zero & size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(InfinityMirrorPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.depth != depth;
}
