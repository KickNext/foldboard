import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../domain/models/architecture_models.dart';
import '../../../../core/app_theme.dart';
import '../../view_models/planner_view_model.dart';
import 'inspector_panel.dart';

/// An overlay: opening details never resizes or transforms the board.
class FloatingInspector extends StatefulWidget {
  const FloatingInspector({
    super.key,
    required this.viewModel,
    required this.visible,
    required this.onClose,
    this.onAskAgent,
  });

  final PlannerViewModel viewModel;
  final bool visible;
  final VoidCallback onClose;
  final VoidCallback? onAskAgent;

  @override
  State<FloatingInspector> createState() => _FloatingInspectorState();
}

class _FloatingInspectorState extends State<FloatingInspector>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  late final AnimationController _replacement;
  late final Animation<double> _reveal;
  ArchitectureNode? _node;
  ArchitectureGroup? _group;
  ArchitectureNode? _previousNode;
  ArchitectureGroup? _previousGroup;
  bool _hasPrevious = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: AppTheme.panelEnter,
          reverseDuration: AppTheme.panelExit,
        )..addStatusListener((_) {
          if (_controller.isDismissed) {
            _hasPrevious = false;
            _previousNode = null;
            _previousGroup = null;
          }
          if (mounted) setState(() {});
        });
    _progress = _controller.drive(CurveTween(curve: Curves.easeOutCubic));
    _replacement =
        AnimationController(vsync: this, duration: AppTheme.panelSwap, value: 1)
          ..addStatusListener((status) {
            if (status != AnimationStatus.completed || !mounted) return;
            _hasPrevious = false;
            _previousNode = null;
            _previousGroup = null;
            // Rapid clicks coalesce to the latest selection, not a stack of forms.
            if (widget.visible) _syncContent();
            setState(() {});
          });
    _reveal = _replacement.drive(
      CurveTween(curve: Curves.easeInOutCubicEmphasized),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant FloatingInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.visible) {
      _syncContent(immediate: reduceMotion || _controller.isDismissed);
    } else {
      _replacement.stop();
    }
    if (reduceMotion) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _syncContent({bool immediate = false}) {
    final node = widget.viewModel.selectedNode;
    final group = widget.viewModel.selectedGroup;
    final same = (node?.id ?? group?.id) == (_node?.id ?? _group?.id);
    if (immediate) {
      _node = node;
      _group = group;
      _hasPrevious = false;
      _previousNode = null;
      _previousGroup = null;
      _replacement.value = 1;
    } else if (same) {
      _node = node;
      _group = group;
    } else if (!_replacement.isAnimating) {
      _previousNode = _node;
      _previousGroup = _group;
      _hasPrevious = _node != null || _group != null;
      _node = node;
      _group = group;
      _replacement.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _replacement.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final margin = compact ? 12.0 : 16.0;
        final bottomInset = 76.0 + MediaQuery.paddingOf(context).bottom;
        // 168 keeps the notification lane clear, but on very short windows
        // the sheet claims at least 38px instead of collapsing to nothing.
        final top = compact
            ? math.max(
                margin,
                math.min(
                  168.0,
                  constraints.maxHeight - margin - bottomInset - 38,
                ),
              )
            : margin;
        final clearance = bottomInset;
        final alignment = compact ? Alignment.bottomRight : Alignment.topRight;
        return Padding(
          padding: EdgeInsets.fromLTRB(margin, top, margin, margin + clearance),
          child: Align(
            alignment: alignment,
            child: SizedBox(
              width: math.min(
                compact ? 420 : 380,
                constraints.maxWidth - margin * 2,
              ),
              height: math.min(
                compact ? 480 : 560,
                math.max(0, constraints.maxHeight - margin - top - clearance),
              ),
              child: IgnorePointer(
                ignoring: !widget.visible,
                child: ExcludeFocus(
                  excluding: !widget.visible,
                  child: ExcludeSemantics(
                    excluding: !widget.visible,
                    child: FadeTransition(
                      opacity: _progress,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: compact
                              ? const Offset(0, .12)
                              : const Offset(.14, 0),
                          end: Offset.zero,
                        ).animate(_progress),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: .97,
                            end: 1,
                          ).animate(_progress),
                          alignment: alignment,
                          child: RepaintBoundary(
                            child: DecoratedBox(
                              key: const Key('details-surface'),
                              decoration: AppTheme.floatingPanel(context),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFloating,
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: _buildSheets(context),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sheet(
    BuildContext context,
    ArchitectureNode? node,
    ArchitectureGroup? group,
  ) => DecoratedBox(
    decoration: AppTheme.inspectorSheet(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final panel = InspectorPanel(
          scrollWhole: constraints.maxHeight < 240,
          key: ValueKey('details-${node?.id ?? group?.id}'),
          viewModel: widget.viewModel,
          node: node,
          group: group,
          onClose: widget.onClose,
          onAskAgent: widget.onAskAgent,
        );
        if (constraints.maxHeight >= 240) return panel;
        // Short windows keep the toolbar/notification lane clear. The entire
        // sheet scrolls instead of squeezing its fixed header and footer.
        return SingleChildScrollView(
          key: const Key('short-inspector-scroll'),
          child: panel,
        );
      },
    ),
  );

  Widget _buildSheets(BuildContext context) => Stack(
    key: const Key('inspector-content-transition'),
    fit: StackFit.expand,
    children: [
      if (_hasPrevious)
        IgnorePointer(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: _sheet(context, _previousNode, _previousGroup),
            ),
          ),
        ),
      CustomPaint(
        key: const Key('inspector-current-layer'),
        painter: _RevealEdge(_reveal, context.colors),
        child: ClipPath(
          key: const Key('inspector-reveal'),
          clipper: _SheetReveal(_reveal),
          child: ExcludeFocus(
            excluding: _replacement.isAnimating,
            child: _sheet(context, _node, _group),
          ),
        ),
      ),
    ],
  );
}

// Only the clip and its narrow shadow repaint; text and fields never move.
class _SheetReveal extends CustomClipper<Path> {
  _SheetReveal(this.progress) : super(reclip: progress);
  final Animation<double> progress;
  @override
  Path getClip(Size size) {
    final t = progress.value;
    if (t <= 0) return Path();
    if (t >= 1) return Path()..addRect(Offset.zero & size);
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          size.width * (1 - t),
          -24,
          size.width + 24,
          size.height + 24,
        ),
        Radius.circular(24 * (1 - t)),
      ),
    );
  }

  @override
  bool shouldReclip(covariant _SheetReveal oldClipper) =>
      oldClipper.progress != progress;
}

class _RevealEdge extends CustomPainter {
  _RevealEdge(this.progress, this.palette) : super(repaint: progress);
  final Animation<double> progress;
  final AppPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final x = size.width * (1 - t);
    final rect = Rect.fromLTWH(x - 20, 0, 20, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            palette.text.withValues(alpha: 0),
            palette.text.withValues(alpha: .12 * math.sin(t * math.pi)),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RevealEdge oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.progress != progress;
}
