import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/app_theme.dart';
import 'reference_portal.dart';

/// Opaque in flight. On landing, clear the old scene before revealing the card
/// through the same aperture, so text neither doubles nor pops on the last frame.
class LevelPortalTransition extends StatefulWidget {
  const LevelPortalTransition({
    super.key,
    required this.levelId,
    required this.entering,
    required this.portalBounds,
    this.portalRadius = AppTheme.radiusProcessCard,
    required this.sourceOrigin,
    this.destinationOrigin,
    required this.viewport,
    required this.child,
  });
  final String? levelId;
  final bool entering;
  final Rect? portalBounds;
  final double portalRadius;
  final Offset sourceOrigin;
  final Offset? destinationOrigin;
  final Size viewport;
  final Widget child;
  @override
  State<LevelPortalTransition> createState() => _LevelPortalTransitionState();
}

class _LevelPortalTransitionState extends State<LevelPortalTransition>
    with SingleTickerProviderStateMixin {
  final _viewportKey = GlobalKey();
  late final AnimationController _flight =
      AnimationController(
        vsync: this,
        duration: AppTheme.portalTransition,
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _previous = null);
        }
      });
  Widget? _previous;
  Map<Key, double> _hoverValues = {};
  Map<Key, double> _previousHover = const {};

  @override
  void didUpdateWidget(LevelPortalTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.levelId == widget.levelId) {
      if (oldWidget.viewport != widget.viewport && _previous != null) {
        _flight.stop();
        _previous = null;
      }
      return;
    }
    _previousHover = Map.of(_hoverValues);
    _hoverValues = {};
    if (MediaQuery.disableAnimationsOf(context) ||
        widget.portalBounds == null) {
      _previous = null;
      _flight.stop();
    } else {
      // Coalesce rapid navigation; never keep a queue of old scenes.
      _previous = oldWidget.child;
      _flight.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _previous = null;
      _flight.value = 1;
    }
  }

  @override
  void dispose() {
    _flight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _flight,
    builder: (context, _) {
      final liveScene = ReferenceHoverScene(
        values: _hoverValues,
        child: widget.child,
      );
      final destination = widget.destinationOrigin == null
          ? liveScene
          : _OriginLockedScene(
              origin: widget.destinationOrigin!,
              child: liveScene,
            );
      if (_previous == null) return destination;
      return IgnorePointer(
        child: ExcludeFocus(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final full = Offset.zero & constraints.biggest;
              final progress = AppTheme.portalCurve.transform(_flight.value);
              final expansion = widget.entering ? progress : 1 - progress;
              final clipper = PortalApertureClipper(() {
                var card = widget.portalBounds!;
                if (widget.entering || widget.destinationOrigin != null) {
                  // Resolve after layout: breadcrumbs, banners and window size
                  // can move the canvas independently of its dimensions.
                  final box = _viewportKey.currentContext?.findRenderObject();
                  if (box is RenderBox && box.hasSize) {
                    card = card.shift(
                      (widget.entering
                              ? widget.sourceOrigin
                              : widget.destinationOrigin!) -
                          box.localToGlobal(Offset.zero),
                    );
                  }
                }
                return RRect.fromRectAndRadius(
                  Rect.lerp(card, full, expansion)!,
                  Radius.circular(widget.portalRadius * (1 - expansion)),
                );
              });
              final incoming = RepaintBoundary(
                key: const Key('portal-incoming'),
                child: ColoredBox(
                  color: context.colors.background,
                  child: destination,
                ),
              );
              final outgoing = ExcludeSemantics(
                child: RepaintBoundary(
                  key: const Key('portal-outgoing'),
                  child: ColoredBox(
                    color: context.colors.background,
                    child: _OriginLockedScene(
                      origin: widget.sourceOrigin,
                      child: ReferenceHoverScene(
                        values: _previousHover,
                        frozen: true,
                        child: _previous!,
                      ),
                    ),
                  ),
                ),
              );
              return ClipRect(
                key: _viewportKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    widget.entering ? outgoing : incoming,
                    ClipRRect(
                      key: const Key('portal-aperture'),
                      clipper: clipper,
                      child: widget.entering
                          ? incoming
                          : Opacity(
                              key: const Key('portal-exit-reveal'),
                              opacity:
                                  1 -
                                  AppTheme.portalExitReveal.transform(
                                    _flight.value,
                                  ),
                              child: ColoredBox(
                                color: context.colors.surface,
                                child: Opacity(
                                  key: const Key('portal-exit-scene'),
                                  opacity:
                                      1 -
                                      AppTheme.portalExitVeil.transform(
                                        _flight.value,
                                      ),
                                  child: outgoing,
                                ),
                              ),
                            ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _PortalRimPainter(
                          clipper,
                          context.colors.accent,
                          math.sin(math.pi * _flight.value),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

class PortalApertureClipper extends CustomClipper<RRect> {
  const PortalApertureClipper(this.resolve);
  final RRect Function() resolve;
  RRect get aperture => resolve();
  @override
  RRect getClip(Size size) => aperture;
  @override
  bool shouldReclip(PortalApertureClipper oldClipper) =>
      resolve != oldClipper.resolve;
}

class _PortalRimPainter extends CustomPainter {
  const _PortalRimPainter(this.clipper, this.color, this.intensity);
  final PortalApertureClipper clipper;
  final Color color;
  final double intensity;
  @override
  void paint(Canvas canvas, Size size) {
    final aperture = clipper.getClip(size);
    canvas.drawRRect(
      aperture,
      Paint()
        ..color = color.withValues(alpha: .07 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawRRect(
      aperture,
      Paint()
        ..color = color.withValues(alpha: .55 * intensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PortalRimPainter oldDelegate) =>
      clipper != oldDelegate.clipper ||
      color != oldDelegate.color ||
      intensity != oldDelegate.intensity;
}

/// Keep the outgoing scene at its captured screen origin while the destination
/// page lays out. This is a paint transform, never an inferred height delta.
class _OriginLockedScene extends SingleChildRenderObjectWidget {
  const _OriginLockedScene({required this.origin, super.child});
  final Offset origin;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOriginLockedScene(origin);
  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOriginLockedScene renderObject,
  ) {
    renderObject.origin = origin;
  }
}

class _RenderOriginLockedScene extends RenderProxyBox {
  _RenderOriginLockedScene(this._origin);
  Offset _origin;
  set origin(Offset value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  Offset get _shift => _origin - localToGlobal(Offset.zero);
  @override
  void paint(PaintingContext context, Offset offset) =>
      super.paint(context, offset + _shift);
  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    final delta = _shift;
    transform.translateByDouble(delta.dx, delta.dy, 0, 1);
  }
}
