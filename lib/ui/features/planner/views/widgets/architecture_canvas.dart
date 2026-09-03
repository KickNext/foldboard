import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:flutter/services.dart';

import '../../../../../domain/models/architecture_models.dart';
import '../../../../../domain/models/board_request.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/write_access_scope.dart';
import '../../view_models/canvas_camera.dart';
import '../../view_models/edge_routes.dart';
import '../../view_models/planner_view_model.dart';
import '../../view_models/level_graph.dart';
import 'connection_arrow.dart';
import 'process_portal.dart';
import 'reference_portal.dart';
import 'level_portal_transition.dart';
import 'agent_pulse.dart';
import 'board_tool_dock.dart';

enum _ConnectionSide { left, right, top, bottom }

class ArchitectureCanvas extends StatefulWidget {
  const ArchitectureCanvas({
    super.key,
    required this.viewModel,
    this.fitOnStart = false,
    this.showGrid = true,
    this.onOpenDetails,
    this.onOpenComments,
    this.captureKey,
  });
  final PlannerViewModel viewModel;
  final bool fitOnStart;
  final bool showGrid;
  final VoidCallback? onOpenDetails;
  final VoidCallback? onOpenComments;

  /// Attached to the board layer so Export PNG can rasterise it.
  final GlobalKey? captureKey;
  @override
  State<ArchitectureCanvas> createState() => _ArchitectureCanvasState();
}

class _ArchitectureCanvasState extends State<ArchitectureCanvas>
    with TickerProviderStateMixin {
  static const nodeSize = Size(260, 118);
  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _dockKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();
  final GlobalKey _pathKey = GlobalKey();
  final GlobalKey _zoomKey = GlobalKey();
  final GlobalKey _minimapKey = GlobalKey();
  final GlobalKey _popoverKey = GlobalKey();
  // Marker anchor key ('<nodeId>' or 'edge:<viewEdgeId>') → its target IDs.
  String? _commentAnchor;
  Set<String> _commentAnchorIds = const {};

  bool _overWidget(GlobalKey key, Offset position) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).contains(position);
  }

  bool _overControls(Offset position) => [
    _dockKey,
    _historyKey,
    _pathKey,
    _zoomKey,
    _minimapKey,
    _popoverKey,
  ].any((key) => _overWidget(key, position));
  late final CanvasCamera _camera;
  Offset? _lastFocal;
  Offset? _globalPanLast;
  String? _dragNodeId;
  String? _frontNodeId;
  Offset? _dragStartWorld;
  Map<String, Offset> _dragStartPositions = const {};
  Map<String, Offset> _dragPositions = const {};
  bool _dragSelectionPrepared = false;
  bool _dragAdditive = false;
  String? _connectionDragFrom;
  String? _connectionTargetId;
  Offset? _connectionDragPoint;
  String? _hoveredConnectionNodeId;
  _ConnectionSide? _hoveredConnectionSide;
  _ConnectionSide? _connectionDragSide;
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;
  bool _marqueeAdditive = false;
  bool _suppressBackgroundTap = false;
  double _gestureStartScale = 1;
  int _cameraRequest = -1;
  int _agentCameraVersion = -1;
  bool _firstLayout = true;
  // While armed, the opening fit re-checks itself every frame; any manual
  // pan or zoom (or a selection) hands the camera over to the person.
  bool _autoFitArmed = false;
  late final AnimationController _arrangeAnimation;
  late final AnimationController _edgeIgnition;
  String? _litNodeId;
  int _arrangeVersion = 0;
  int _animationRevision = -1;
  String? _levelId;
  List<String> _levelPath = const [];
  final _levelCameras = <String?, (double, Offset, Size)>{};
  bool _enteringLevel = true;
  Rect? _portalBounds;
  double _portalRadius = AppTheme.radiusProcessCard;
  Offset _sourceOrigin = Offset.zero;
  Rect? _referenceAnchor;
  Offset? _referenceOrigin;
  int _referenceAlignmentVersion = 0;
  bool _pendingLevel = false;
  String? _returnPortalId;
  List<ArchitectureNode> _displayNodes = const [];
  final _router = EdgeRouter();
  final _dragRouter = EdgeRouter();
  final _targetRouter = EdgeRouter();
  List<EdgeRoute> _routes = const [];
  Map<String, Offset> _arrangeFrom = {};
  List<ArchitectureNode>? _boundsNodes;
  List<EdgeRoute>? _boundsRoutes;
  Rect? _cachedContentBounds;

  @override
  void initState() {
    super.initState();
    _camera = CanvasCamera();
    widget.viewModel.readViewport = _viewportContext;
    _camera.addListener(_cameraChanged);
    _arrangeVersion = widget.viewModel.arrangeVersion;
    _levelId = widget.viewModel.currentLevelId;
    _levelPath = widget.viewModel.levelPath.map((g) => g.id).toList();
    _arrangeAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..addListener(_animateArrange);
    _litNodeId =
        widget.viewModel.selectedId ?? widget.viewModel.selectedGroupId;
    _edgeIgnition = AnimationController(
      vsync: this,
      duration: AppTheme.edgeIgnition,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _edgeIgnition.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant ArchitectureCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final vm = widget.viewModel;
    if (oldWidget.viewModel != vm) {
      oldWidget.viewModel.readViewport = null;
      vm.readViewport = _viewportContext;
    }
    final litNode = vm.selectedEdgeId == null
        ? vm.selectedId ?? vm.selectedGroupId
        : null;
    if (litNode != _litNodeId || oldWidget.viewModel != vm) {
      _litNodeId = litNode;
      if (litNode == null || MediaQuery.disableAnimationsOf(context)) {
        _edgeIgnition.value = 1;
      } else {
        _edgeIgnition.forward(from: 0);
      }
    }
    if (oldWidget.viewModel != vm || _levelId != vm.currentLevelId) {
      _commentAnchor = null;
      _commentAnchorIds = const {};
      _stopArrange();
      _arrangeVersion = vm.arrangeVersion;
      if (oldWidget.viewModel == vm) {
        _prepareLevelTransition();
      } else {
        _levelCameras.clear();
        _referenceAlignmentVersion++;
        _referenceOrigin = null;
        _referenceAnchor = null;
      }
    } else if (_arrangeVersion != vm.arrangeVersion) {
      _arrangeVersion = vm.arrangeVersion;
      _startArrange();
    } else if (_arrangeAnimation.isAnimating &&
        (_animationRevision != vm.repository.revision ||
            _cameraRequest != vm.cameraRequestVersion)) {
      _stopArrange();
    }
    _levelId = vm.currentLevelId;
    _levelPath = vm.levelPath.map((g) => g.id).toList();
  }

  void _prepareLevelTransition() {
    if (_camera.viewport.isEmpty) return;
    final vm = widget.viewModel;
    final nextPath = vm.levelPath.map((g) => g.id).toList();
    bool prefix(List<String> a, List<String> b) =>
        a.length <= b.length &&
        List.generate(a.length, (i) => a[i] == b[i]).every((same) => same);
    _enteringLevel =
        vm.referenceTargetId == null &&
        nextPath.length > _levelPath.length &&
        prefix(_levelPath, nextPath);
    final exiting =
        nextPath.length < _levelPath.length && prefix(nextPath, _levelPath);
    _levelCameras[_levelId] = (
      _camera.scale,
      _camera.translation,
      _camera.viewport,
    );
    final sourceBox = _canvasKey.currentContext?.findRenderObject();
    _sourceOrigin = sourceBox is RenderBox
        ? sourceBox.localToGlobal(Offset.zero)
        : Offset.zero;
    _portalBounds = null;
    _referenceAnchor = null;
    _referenceOrigin = null;
    _referenceAlignmentVersion++;
    _portalRadius = AppTheme.radiusProcessCard;
    _returnPortalId =
        vm.referenceTargetId ?? (exiting ? _levelPath[nextPath.length] : null);
    if (vm.referenceTargetId != null) {
      final reference = _displayNodes
          .where((n) => n.id == vm.referenceTargetId)
          .firstOrNull;
      if (reference != null) {
        _referenceAnchor =
            _camera.worldToScreen(reference.position) &
            (nodeSize * _camera.scale);
      }
    }
    if (_enteringLevel) {
      final portalId = nextPath[_levelPath.length];
      final portal = _displayNodes.where((n) => n.id == portalId).firstOrNull;
      if (portal != null) {
        final anchor =
            _camera.worldToScreen(portal.position) & (nodeSize * _camera.scale);
        if (anchor.overlaps(Offset.zero & _camera.viewport)) {
          _portalBounds = anchor;
        }
      }
    }
    // Camera fitting waits for the destination's actual layout, including its
    // breadcrumb row. Source geometry has already been captured above.
    _pendingLevel = true;
    _dragNodeId = null;
    _dragStartWorld = null;
    _dragStartPositions = const {};
    _dragPositions = const {};
    _dragSelectionPrepared = false;
    _globalPanLast = null;
    _lastFocal = null;
    _frontNodeId = null;
  }

  void _finishLevelTransition() {
    final vm = widget.viewModel;
    final remembered = _levelCameras[vm.currentLevelId];
    final reference = vm.canvasNodes
        .where((n) => n.id == vm.referenceTargetId)
        .firstOrNull;
    final anchored = reference != null && _referenceAnchor != null;
    if (anchored) {
      final anchor = _referenceAnchor!;
      final scale = anchor.width / nodeSize.width;
      _camera.setTransform(
        scale: scale,
        translation: anchor.topLeft - reference.position * scale,
      );
      // Until layout finishes, paint the destination at the captured source
      // origin. Commit that offset into the camera without a one-frame jump.
      _referenceOrigin = _sourceOrigin;
      final version = _referenceAlignmentVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            version != _referenceAlignmentVersion ||
            _referenceOrigin == null) {
          return;
        }
        final box = _canvasKey.currentContext?.findRenderObject();
        if (box is! RenderBox) return;
        final delta = _referenceOrigin! - box.localToGlobal(Offset.zero);
        _referenceOrigin = null;
        _portalBounds = _portalBounds?.shift(delta);
        _camera.pan(delta);
      });
    } else if (remembered != null && vm.cameraTargetId == null) {
      // Restore on re-entry too. If the window changed, preserve the world point
      // at its center, rather than unexpectedly fitting the entire level again.
      final delta =
          _camera.viewport.center(Offset.zero) -
          remembered.$3.center(Offset.zero);
      _camera.setTransform(
        scale: remembered.$1,
        translation: remembered.$2 + delta,
      );
    } else if (vm.referenceTargetId == null) {
      final target = vm.canvasNodes
          .where((n) => n.id == vm.cameraTargetId)
          .firstOrNull;
      if (target == null) {
        _fitAll();
      } else {
        _camera.fitBounds(
          (target.position & nodeSize).inflate(120),
          padding: 70,
        );
      }
    }
    if (vm.referenceTargetId != null && !anchored) {
      final target = vm.canvasNodes
          .where((n) => n.id == vm.referenceTargetId)
          .firstOrNull;
      if (target != null) {
        final bounds =
            _camera.worldToScreen(target.position) & (nodeSize * _camera.scale);
        final safe = (Offset.zero & _camera.viewport).deflate(70);
        // Keep a remembered view exactly when the original is already visible.
        // Otherwise pan only: following a reference must never change zoom.
        if (remembered == null ||
            !safe.contains(bounds.topLeft) ||
            !safe.contains(bounds.bottomRight)) {
          _camera.pan(_camera.viewport.center(Offset.zero) - bounds.center);
        }
      }
    }
    if (_returnPortalId != null) {
      final portal = vm.canvasNodes
          .where((n) => n.id == _returnPortalId)
          .firstOrNull;
      if (portal != null) {
        _portalRadius = vm.levelGraph.processIds.contains(portal.id)
            ? AppTheme.radiusProcessCard
            : AppTheme.radiusCard;
        final anchor =
            _camera.worldToScreen(portal.position) & (nodeSize * _camera.scale);
        if (anchor.overlaps(Offset.zero & _camera.viewport)) {
          _portalBounds = anchor;
        }
      }
    }
    _cameraRequest = vm.cameraRequestVersion;
    _firstLayout = false;
    _pendingLevel = false;
  }

  void _startArrange() {
    _arrangeAnimation.stop();
    _arrangeFrom = {for (final n in _displayNodes) n.id: n.position};
    _animationRevision = widget.viewModel.repository.revision;
    _cameraRequest = widget.viewModel.cameraRequestVersion;
    // Arrange ends framed: without a fit a small tidy-up can be invisible
    // and the button reads as broken. The cards animate into an
    // already-framed layout.
    if (widget.viewModel.canvasNodes.any(
      (n) => _arrangeFrom[n.id] != null && _arrangeFrom[n.id] != n.position,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitAll();
      });
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _arrangeFrom = {};
    } else {
      _arrangeAnimation.forward(from: 0);
    }
  }

  void _animateArrange() {
    if (_arrangeAnimation.isCompleted) _arrangeFrom = {};
    setState(() {});
  }

  void _stopArrange() {
    _arrangeAnimation.stop();
    _arrangeFrom = {};
  }

  @override
  void dispose() {
    widget.viewModel.readViewport = null;
    _edgeIgnition.dispose();
    _arrangeAnimation.dispose();
    _camera.removeListener(_cameraChanged);
    _camera.dispose();
    super.dispose();
  }

  void _cameraChanged() {
    // The destination camera is applied inside LayoutBuilder, which is already
    // producing the new scene. It must not schedule its ancestor during layout.
    if (mounted && !_pendingLevel) setState(() {});
  }

  Map<String, dynamic> _viewportContext() {
    final rect = _camera.visibleWorldRect;
    final visible = _displayNodes
        .where((n) => (n.position & nodeSize).overlaps(rect))
        .map((n) => n.id)
        .toList();
    return {
      'levelId': _levelId,
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'zoom': _camera.scale,
      'visibleIds': visible.take(200).toList(),
      'visibleCount': visible.length,
      'truncated': visible.length > 200,
    };
  }

  Rect get _contentBounds {
    final nodes = widget.viewModel.canvasNodes;
    final routes = _targetRouter.route(nodes, widget.viewModel.canvasEdges);
    if (identical(nodes, _boundsNodes) && identical(routes, _boundsRoutes)) {
      return _cachedContentBounds!;
    }
    final rects = <Rect>[
      ...nodes.map((n) => n.position & nodeSize),
      ...routes.map((route) => route.bounds.inflate(12)),
    ];
    final result = rects.isEmpty
        ? const Rect.fromLTWH(0, 0, 1000, 700)
        : rects.reduce((a, b) => a.expandToInclude(b));
    _boundsNodes = nodes;
    _boundsRoutes = routes;
    return _cachedContentBounds = result;
  }

  void _fitAll() {
    if (widget.viewModel.canvasNodes.isEmpty) {
      if (_camera.viewport.isEmpty) return;
      // An empty level has no content to fit. Keep a neutral 100% camera and
      // put world origin in the visual centre so the first card appears near
      // where the person is looking.
      _camera.setTransform(
        scale: 1,
        translation: _camera.viewport.center(Offset.zero),
      );
      return;
    }
    _camera.fitBounds(_contentBounds, padding: 56);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        _camera.setViewport(viewport);
        if (_pendingLevel) _finishLevelTransition();
        final t = Curves.easeInOutCubic.transform(_arrangeAnimation.value);
        final arrangedNodes = _arrangeFrom.isEmpty
            ? widget.viewModel.canvasNodes
            : [
                for (final node in widget.viewModel.canvasNodes)
                  if (_arrangeFrom.containsKey(node.id))
                    node.copyWith(
                      position: Offset.lerp(
                        _arrangeFrom[node.id],
                        node.position,
                        t,
                      ),
                    )
                  else
                    node,
              ];
        _displayNodes = _dragPositions.isEmpty
            ? arrangedNodes
            : [
                for (final node in arrangedNodes)
                  if (_dragPositions[node.id] case final position?)
                    node.copyWith(position: position)
                  else
                    node,
              ];
        final edges = widget.viewModel.canvasEdges;
        if (_dragPositions.isEmpty) {
          _routes = _router.route(_displayNodes, edges);
        } else {
          final moved = _dragPositions.keys.toSet();
          final movingEdges = edges
              .where(
                (edge) => moved.contains(edge.from) || moved.contains(edge.to),
              )
              .toList();
          final stableRoutes = _router.route(
            widget.viewModel.canvasNodes,
            edges,
          );
          _routes = [
            for (final route in stableRoutes)
              if (!moved.contains(route.edge.from) &&
                  !moved.contains(route.edge.to))
                route,
            ..._dragRouter.route(_displayNodes, movingEdges),
          ];
        }
        if (_firstLayout ||
            _cameraRequest != widget.viewModel.cameraRequestVersion) {
          final shouldFocus =
              (!_firstLayout ||
              widget.fitOnStart ||
              widget.viewModel.cameraRequestVersion > 0);
          // Until the person touches the camera, the opening fit keeps
          // following viewport changes: the first layout can run against a
          // stale window size, which used to leave the board cut off at one
          // edge.
          _autoFitArmed =
              _firstLayout &&
              widget.fitOnStart &&
              widget.viewModel.canvasNodes.isNotEmpty &&
              widget.viewModel.cameraTargetId == null;
          _cameraRequest = widget.viewModel.cameraRequestVersion;
          _firstLayout = false;
          if (shouldFocus) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final id = widget.viewModel.cameraTargetId;
              final node = widget.viewModel.canvasNodes
                  .where((n) => n.id == id)
                  .firstOrNull;
              if (node == null) {
                _fitAll();
              } else {
                _camera.fitBounds(
                  (node.position & nodeSize).inflate(120),
                  padding: 70,
                );
              }
            });
          }
        }
        if (_agentCameraVersion != widget.viewModel.agentChangeVersion) {
          _agentCameraVersion = widget.viewModel.agentChangeVersion;
          final version = _agentCameraVersion;
          final createdIds = widget.viewModel.agentCreatedIds;
          if (createdIds.isNotEmpty) {
            _autoFitArmed = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || version != widget.viewModel.agentChangeVersion) {
                return;
              }
              final targets = widget.viewModel.canvasNodes
                  .where((node) => createdIds.contains(node.id))
                  .toList();
              if (targets.isEmpty) return;
              final bounds = targets
                  .map((node) => node.position & nodeSize)
                  .reduce((a, b) => a.expandToInclude(b));
              // Show what the agent created while preserving the person's
              // current zoom whenever the new cards fit at that scale.
              _camera.fitBounds(bounds, padding: 90, maxScale: _camera.scale);
            });
          }
        }
        // Any selection means the person is working here; the camera is
        // theirs from that point on.
        if (widget.viewModel.hasSelection) _autoFitArmed = false;
        // Until then the opening fit keeps itself honest: browsers settle
        // the window size (and thus the first fit) a few frames late, which
        // used to leave the board cut off at one edge.
        if (_autoFitArmed && !_firstLayout && !viewport.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_autoFitArmed) return;
            final bounds = _contentBounds;
            final seen = _camera.visibleWorldRect.inflate(1);
            if (!seen.contains(bounds.topLeft) ||
                !seen.contains(bounds.bottomRight)) {
              _fitAll();
            }
          });
        }
        final visible = _camera.visibleWorldRect.inflate(180 / _camera.scale);
        return Listener(
          key: _canvasKey,
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            // Clicking anywhere outside the popover puts the thread away,
            // exactly like anchored comments in canvas editors.
            if (_commentAnchor != null &&
                !_overWidget(_popoverKey, event.position)) {
              setState(() {
                _commentAnchor = null;
                _commentAnchorIds = const {};
              });
            }
            if (_overControls(event.position)) return;
            _autoFitArmed = false;
            if (_wantsGlobalPan(event.buttons)) {
              _globalPanLast = event.localPosition;
            } else {
              final keyboard = HardwareKeyboard.instance;
              final additive =
                  keyboard.isShiftPressed ||
                  keyboard.isControlPressed ||
                  keyboard.isMetaPressed;
              if (event.buttons & kPrimaryMouseButton == 0 ||
                  widget.viewModel.canvasTool != CanvasTool.select ||
                  !additive ||
                  _pointOverNode(event.localPosition)) {
                return;
              }
              setState(() {
                _marqueeStart = event.localPosition;
                _marqueeCurrent = event.localPosition;
                _marqueeAdditive = true;
              });
            }
          },
          onPointerHover: _updateConnectionHover,
          onPointerMove: (event) {
            if (_marqueeStart != null) {
              setState(() => _marqueeCurrent = event.localPosition);
            } else if (_globalPanLast != null &&
                _wantsGlobalPan(event.buttons)) {
              _camera.pan(event.localPosition - _globalPanLast!);
              _globalPanLast = event.localPosition;
            }
          },
          onPointerUp: (_) {
            _globalPanLast = null;
            _finishMarquee();
          },
          onPointerCancel: (_) {
            _globalPanLast = null;
            if (_marqueeStart != null) {
              setState(() {
                _marqueeStart = null;
                _marqueeCurrent = null;
              });
            }
          },
          onPointerSignal: (event) {
            if (_overControls(event.position)) return;
            if (event is PointerScrollEvent) {
              // Nested scrollable widgets get first refusal on the wheel.
              GestureBinding.instance.pointerSignalResolver.register(event, (
                _,
              ) {
                _autoFitArmed = false;
                final factor = math.exp(-event.scrollDelta.dy * .0014);
                _camera.zoomBy(event.localPosition, factor);
              });
            }
          },
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  // Only the world layer is captured by Export PNG; the
                  // floating controls are siblings outside this boundary.
                  child: RepaintBoundary(
                    key: widget.captureKey,
                    child: LevelPortalTransition(
                      levelId: widget.viewModel.currentLevelId,
                      entering: _enteringLevel,
                      portalRadius:
                          _portalRadius *
                          ((_portalBounds?.width ?? nodeSize.width) /
                              nodeSize.width),
                      portalBounds: _portalBounds,
                      sourceOrigin: _sourceOrigin,
                      destinationOrigin: _referenceOrigin,
                      viewport: viewport,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) =>
                                  _selectAt(details.localPosition),
                              onScaleStart: (details) {
                                _lastFocal = details.localFocalPoint;
                                _gestureStartScale = _camera.scale;
                              },
                              onScaleUpdate: (details) {
                                if (_marqueeStart != null) return;
                                final previous =
                                    _lastFocal ?? details.localFocalPoint;
                                if ((details.scale - 1).abs() > .002) {
                                  _camera.zoomAt(
                                    details.localFocalPoint,
                                    _gestureStartScale * details.scale,
                                  );
                                } else if (_globalPanLast == null) {
                                  // The outer pointer listener already pans in hand,
                                  // Space and middle-button modes, including over nodes.
                                  // Only handle background-only panning here.
                                  _autoFitArmed = false;
                                  _camera.pan(
                                    details.localFocalPoint - previous,
                                  );
                                }
                                _lastFocal = details.localFocalPoint;
                              },
                              child: CustomPaint(
                                painter: _ViewportPainter(
                                  showGrid: widget.showGrid,
                                  palette: context.colors,
                                  camera: CanvasCamera(
                                    scale: _camera.scale,
                                    translation: _camera.translation,
                                  )..setViewport(_camera.viewport),
                                  nodes: _displayNodes,
                                  routes: _routes,
                                  selectedNodeId:
                                      widget.viewModel.selectedId ??
                                      widget.viewModel.selectedGroupId,
                                  selectedEdgeId:
                                      widget.viewModel.selectedEdgeId,
                                  ignition: _edgeIgnition,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                          ..._systemChildren(visible),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_connectionDragFrom != null && _connectionDragPoint != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const Key('connection-drag-preview'),
                        painter: _ConnectionDragPainter(
                          start: _connectionStartPoint,
                          end: _connectionEndPoint,
                          startDirection: _connectionStartDirection,
                          endDirection: _connectionEndDirection,
                          color: context.colors.accent,
                        ),
                      ),
                    ),
                  ),
                if (_clickConnectionPreview case final preview?)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const Key('connection-hover-preview'),
                        painter: _ConnectionDragPainter(
                          start: preview.start,
                          end: preview.end,
                          startDirection: preview.startDirection,
                          endDirection: preview.endDirection,
                          color: context.colors.accent,
                        ),
                      ),
                    ),
                  ),
                if (_marqueeRect case final rect?)
                  Positioned.fromRect(
                    rect: rect,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const Key('selection-marquee'),
                        decoration: BoxDecoration(
                          color: context.colors.accent.withValues(alpha: .10),
                          border: Border.all(
                            color: context.colors.accent.withValues(alpha: .8),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 14,
                  top: 14,
                  right: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BoardHistoryControls(
                        key: _historyKey,
                        viewModel: widget.viewModel,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: LevelPathBar(
                            key: _pathKey,
                            viewModel: widget.viewModel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 16 + MediaQuery.paddingOf(context).bottom,
                  child: Align(
                    alignment: viewport.width < 900
                        ? Alignment.bottomLeft
                        : Alignment.bottomCenter,
                    child: BoardToolDock(
                      key: _dockKey,
                      viewModel: widget.viewModel,
                      showLabels: viewport.width >= 900,
                      onAdd: (type) {
                        final vm = widget.viewModel;
                        type == 'node'
                            ? vm.addNode(title: '')
                            : vm.addGroup(title: '');
                        widget.onOpenDetails?.call();
                        vm.focusSelection();
                      },
                    ),
                  ),
                ),
                if (viewport.width >= 900 &&
                    widget.viewModel.canvasNodes.isNotEmpty &&
                    !(_camera.visibleWorldRect.contains(
                          _contentBounds.topLeft,
                        ) &&
                        _camera.visibleWorldRect.contains(
                          _contentBounds.bottomRight,
                        )))
                  Positioned(
                    left: 14,
                    bottom: 16 + MediaQuery.paddingOf(context).bottom,
                    child: _MiniMap(
                      key: _minimapKey,
                      camera: _camera,
                      bounds: _contentBounds,
                      nodes: _displayNodes,
                    ),
                  ),
                Positioned(
                  right: 14,
                  bottom: 22 + MediaQuery.paddingOf(context).bottom,
                  child: _CanvasControls(
                    key: _zoomKey,
                    compact: viewport.width < 660,
                    scale: _camera.scale,
                    canArrange:
                        widget.viewModel.canEdit &&
                        WriteAccessScope.canWriteOf(context),
                    onTidy: widget.viewModel.arrangeCurrent,
                    onRebuild: () =>
                        widget.viewModel.arrangeCurrent(rebuild: true),
                    onMinus: () {
                      _autoFitArmed = false;
                      _camera.zoomBy(_camera.viewport.center(Offset.zero), .82);
                    },
                    onPlus: () {
                      _autoFitArmed = false;
                      _camera.zoomBy(
                        _camera.viewport.center(Offset.zero),
                        1.22,
                      );
                    },
                    onFit: _fitAll,
                  ),
                ),
                ..._commentLayer(visible, viewport),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _wantsGlobalPan(int buttons) =>
      buttons & kMiddleMouseButton != 0 ||
      (widget.viewModel.canvasTool == CanvasTool.pan &&
          buttons & kPrimaryMouseButton != 0) ||
      HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.space);

  // Labels are optional; the actual line remains a selectable target at any zoom.
  void _selectAt(Offset point) {
    if (_suppressBackgroundTap) {
      _suppressBackgroundTap = false;
      return;
    }
    String? nearestId;
    var bestDistance = 10.0;
    final world = _camera.screenToWorld(point);
    for (final route in _routes) {
      if (!route.bounds.inflate(10 / _camera.scale).contains(world)) continue;
      final distance = route.distanceTo(world) * _camera.scale;
      if (distance < bestDistance) {
        nearestId = route.edge.id;
        bestDistance = distance;
      }
    }
    if (nearestId != null) {
      widget.viewModel.selectEdge(nearestId);
    } else {
      widget.viewModel.select(null);
    }
  }

  Rect? get _marqueeRect {
    final start = _marqueeStart;
    final current = _marqueeCurrent;
    if (start == null || current == null) return null;
    return Rect.fromPoints(start, current);
  }

  bool _pointOverNode(Offset screenPoint) {
    final world = _camera.screenToWorld(screenPoint);
    return _displayNodes.any(
      (node) => (node.position & nodeSize).contains(world),
    );
  }

  void _finishMarquee() {
    final rect = _marqueeRect;
    if (rect == null) return;
    final isDrag = rect.width > 4 || rect.height > 4;
    if (isDrag) {
      final worldRect = Rect.fromPoints(
        _camera.screenToWorld(rect.topLeft),
        _camera.screenToWorld(rect.bottomRight),
      );
      widget.viewModel.selectCards(
        _displayNodes
            .where((node) => worldRect.overlaps(node.position & nodeSize))
            .map((node) => node.id),
        additive: _marqueeAdditive,
      );
      _suppressBackgroundTap = true;
    }
    setState(() {
      _marqueeStart = null;
      _marqueeCurrent = null;
    });
  }

  List<Widget> _systemChildren(Rect visible) {
    final children = <Widget>[];
    final draftTargets = widget.viewModel.commentDraftTargetIds;
    final ordered = <ArchitectureNode>[];
    ArchitectureNode? front;
    for (final node in _displayNodes) {
      if (node.id == _frontNodeId) {
        front = node;
      } else {
        ordered.add(node);
      }
    }
    if (front != null) ordered.add(front);
    for (final node in ordered) {
      final rect = node.position & nodeSize;
      if (!visible.overlaps(rect)) continue;
      children.add(
        _worldWidget(
          rect,
          _NodeCard(
            key: ValueKey('node-${node.id}'),
            node: node,
            selected: widget.viewModel.isCardSelected(node.id),
            connecting:
                widget.viewModel.connectFrom == node.id ||
                _connectionTargetId == node.id ||
                (_hoveredConnectionNodeId == node.id &&
                    widget.viewModel.canConnectTo(node.id)),
            connectionTarget:
                widget.viewModel.connectFrom != null &&
                widget.viewModel.canConnectTo(node.id),
            invalidConnectionTarget:
                widget.viewModel.connectFrom != null &&
                _hoveredConnectionNodeId == node.id &&
                !widget.viewModel.canConnectTo(node.id),
            onTap: () {
              final keyboard = HardwareKeyboard.instance;
              final additive =
                  keyboard.isShiftPressed ||
                  keyboard.isControlPressed ||
                  keyboard.isMetaPressed;
              additive
                  ? widget.viewModel.toggleCardSelection(node.id)
                  : widget.viewModel.selectCard(node.id);
            },
            onFocus: () => widget.viewModel.focusCard(node.id),
            onNudge:
                !widget.viewModel.canEdit ||
                    !WriteAccessScope.canWriteOf(context)
                ? null
                : (delta) => widget.viewModel.isCardSelected(node.id)
                      ? widget.viewModel.nudgeSelection(delta)
                      : widget.viewModel.setNodePosition(
                          node.id,
                          node.position + delta,
                        ),
            onActivate: () {
              final vm = widget.viewModel;
              if (vm.connectFrom != null ||
                  vm.canvasTool != CanvasTool.select ||
                  HardwareKeyboard.instance.isLogicalKeyPressed(
                    LogicalKeyboardKey.space,
                  )) {
                return;
              }
              if (vm.levelGraph.referenceIds.contains(node.id)) {
                vm.openReference(node.id);
              } else if (vm.levelGraph.processIds.contains(node.id)) {
                vm.openLevel(node.id);
              } else {
                vm.select(node.id);
                widget.onOpenDetails?.call();
              }
            },
            activationEnabled:
                widget.viewModel.connectFrom == null &&
                widget.viewModel.canvasTool == CanvasTool.select,
            reference: widget.viewModel.levelGraph.referenceIds.contains(
              node.id,
            ),
            referenceFlow: widget.viewModel.levelGraph.referenceFlows[node.id],
            process:
                widget.viewModel.levelGraph.processIds.contains(node.id) &&
                !widget.viewModel.levelGraph.referenceIds.contains(node.id),
            footer: widget.viewModel.levelGraph.referenceIds.contains(node.id)
                ? (node.id == widget.viewModel.currentLevelId
                      ? context.l10n.thisFold
                      : context.l10n.outside)
                : widget.viewModel.levelGraph.processIds.contains(node.id)
                ? context.l10n.openFold
                : null,
            onOpen: widget.viewModel.levelGraph.referenceIds.contains(node.id)
                ? () => widget.viewModel.openReference(node.id)
                : widget.viewModel.levelGraph.processIds.contains(node.id)
                ? () => widget.viewModel.openLevel(node.id)
                : null,
            onDragStart: (globalPosition) =>
                _startNodeDrag(node, globalPosition),
            onDragUpdate: (globalPosition) =>
                _updateNodeDrag(node.id, globalPosition),
            onDragEnd: _endNodeDrag,
          ),
          nodeId: node.id,
          draftTarget: draftTargets.contains(node.id),
        ),
      );
      // The handle lives on the selected card, not under the pointer: a
      // handle that chases the cursor across every card reads as flicker.
      final selectedCardId =
          widget.viewModel.selectedId ?? widget.viewModel.selectedGroupId;
      if (widget.viewModel.canEdit &&
          WriteAccessScope.canWriteOf(context) &&
          widget.viewModel.canvasTool == CanvasTool.select &&
          (_hoveredConnectionNodeId == node.id ||
              (node.id == selectedCardId &&
                  !widget.viewModel.hasMultipleSelection) ||
              _connectionDragFrom == node.id ||
              widget.viewModel.connectFrom == node.id)) {
        children.add(_connectionHandle(node));
      }
    }
    return children;
  }

  Widget _connectionHandle(ArchitectureNode node) {
    final side = _connectionDragFrom == node.id
        ? _connectionDragSide ?? _ConnectionSide.right
        : _hoveredConnectionNodeId == node.id
        ? _hoveredConnectionSide ?? _ConnectionSide.right
        : _ConnectionSide.right;
    final anchor = _connectionAnchor(node, side);
    final active =
        widget.viewModel.connectFrom == node.id ||
        _connectionDragFrom == node.id ||
        _connectionTargetId == node.id;
    return Positioned(
      key: ValueKey('connection-handle-position-${node.id}'),
      left: anchor.dx - 12,
      top: anchor.dy - 12,
      width: 24,
      height: 24,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: GestureDetector(
          key: ValueKey('connection-handle-${node.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final from = widget.viewModel.connectFrom;
            if (from != null && from != node.id) {
              widget.viewModel.completeConnection(node.id);
            } else {
              widget.viewModel.startConnection(node.id);
            }
          },
          onPanStart: (details) =>
              _startConnectionDrag(node.id, details.globalPosition),
          onPanUpdate: (details) =>
              _updateConnectionDrag(details.globalPosition),
          onPanEnd: (_) => _finishConnectionDrag(),
          onPanCancel: _cancelConnectionDrag,
          child: Center(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              width: active ? 16 : 12,
              height: active ? 16 : 12,
              decoration: BoxDecoration(
                color: active ? context.colors.accent : context.colors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.colors.accent,
                  width: active ? 3 : 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.accent.withValues(alpha: .22),
                    blurRadius: active ? 8 : 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Rect _connectionScreenRect(ArchitectureNode node) =>
      _camera.worldToScreen(node.position) & (nodeSize * _camera.scale);

  Offset _connectionAnchor(ArchitectureNode node, _ConnectionSide side) {
    final rect = _connectionScreenRect(node);
    return switch (side) {
      _ConnectionSide.left => rect.centerLeft,
      _ConnectionSide.right => rect.centerRight,
      _ConnectionSide.top => rect.topCenter,
      _ConnectionSide.bottom => rect.bottomCenter,
    };
  }

  _ConnectionSide _nearestConnectionSide(Rect rect, Offset point) {
    final distances = <_ConnectionSide, double>{
      _ConnectionSide.left: (point.dx - rect.left).abs(),
      _ConnectionSide.right: (point.dx - rect.right).abs(),
      _ConnectionSide.top: (point.dy - rect.top).abs(),
      _ConnectionSide.bottom: (point.dy - rect.bottom).abs(),
    };
    return distances.entries.reduce((a, b) => a.value <= b.value ? a : b).key;
  }

  _ConnectionSide _facingConnectionSide(Rect rect, Offset point) {
    final delta = point - rect.center;
    if (delta.dx.abs() >= delta.dy.abs()) {
      return delta.dx < 0 ? _ConnectionSide.left : _ConnectionSide.right;
    }
    return delta.dy < 0 ? _ConnectionSide.top : _ConnectionSide.bottom;
  }

  Offset _connectionSideDirection(_ConnectionSide side) => switch (side) {
    _ConnectionSide.left => const Offset(-1, 0),
    _ConnectionSide.right => const Offset(1, 0),
    _ConnectionSide.top => const Offset(0, -1),
    _ConnectionSide.bottom => const Offset(0, 1),
  };

  double _distanceToRect(Rect rect, Offset point) {
    final dx = point.dx < rect.left
        ? rect.left - point.dx
        : point.dx > rect.right
        ? point.dx - rect.right
        : 0.0;
    final dy = point.dy < rect.top
        ? rect.top - point.dy
        : point.dy > rect.bottom
        ? point.dy - rect.bottom
        : 0.0;
    return Offset(dx, dy).distance;
  }

  void _updateConnectionHover(PointerHoverEvent event) {
    if (_connectionDragFrom != null) return;
    final canShow =
        widget.viewModel.canEdit &&
        WriteAccessScope.canWriteOf(context) &&
        widget.viewModel.canvasTool == CanvasTool.select &&
        !_overControls(event.position);
    if (!canShow) {
      _clearConnectionHover();
      return;
    }
    final point = event.localPosition;
    final current = _displayNodes
        .where((node) => node.id == _hoveredConnectionNodeId)
        .firstOrNull;
    if (current != null &&
        _hoveredConnectionSide != null &&
        (point - _connectionAnchor(current, _hoveredConnectionSide!))
                .distance <=
            20) {
      return;
    }
    final node = _displayNodes.reversed
        .where((item) => _connectionScreenRect(item).contains(point))
        .firstOrNull;
    if (node == null) {
      _clearConnectionHover();
      return;
    }
    // Hover only steers the handle on the already-selected card; while a
    // connection is open, any card under the pointer is a target and may
    // show one.
    final vm = widget.viewModel;
    if (vm.connectFrom == null &&
        node.id != (vm.selectedId ?? vm.selectedGroupId)) {
      _clearConnectionHover();
      return;
    }
    final source = vm.connectFrom == null
        ? null
        : _displayNodes.where((item) => item.id == vm.connectFrom).firstOrNull;
    final side = source == null
        ? _nearestConnectionSide(_connectionScreenRect(node), point)
        : _facingConnectionSide(
            _connectionScreenRect(node),
            _connectionScreenRect(source).center,
          );
    if (_hoveredConnectionNodeId == node.id && _hoveredConnectionSide == side) {
      return;
    }
    setState(() {
      _hoveredConnectionNodeId = node.id;
      _hoveredConnectionSide = side;
    });
  }

  void _clearConnectionHover() {
    if (_hoveredConnectionNodeId == null) return;
    setState(() {
      _hoveredConnectionNodeId = null;
      _hoveredConnectionSide = null;
    });
  }

  ({Offset start, Offset end, Offset startDirection, Offset endDirection})?
  get _clickConnectionPreview {
    final sourceId = widget.viewModel.connectFrom;
    final targetId = _hoveredConnectionNodeId;
    if (_connectionDragFrom != null ||
        sourceId == null ||
        targetId == null ||
        !widget.viewModel.canConnectTo(targetId)) {
      return null;
    }
    final source = _displayNodes
        .where((node) => node.id == sourceId)
        .firstOrNull;
    final target = _displayNodes
        .where((node) => node.id == targetId)
        .firstOrNull;
    if (source == null || target == null) return null;
    final sourceRect = _connectionScreenRect(source);
    final targetRect = _connectionScreenRect(target);
    final sourceSide = _facingConnectionSide(sourceRect, targetRect.center);
    final targetSide = _facingConnectionSide(targetRect, sourceRect.center);
    return (
      start: _connectionAnchor(source, sourceSide),
      end: _connectionAnchor(target, targetSide),
      startDirection: _connectionSideDirection(sourceSide),
      endDirection: _connectionSideDirection(targetSide) * -1,
    );
  }

  Offset get _connectionStartPoint {
    final source = _displayNodes
        .where((node) => node.id == _connectionDragFrom)
        .firstOrNull;
    return source == null
        ? _connectionDragPoint ?? Offset.zero
        : _connectionAnchor(
            source,
            _connectionDragSide ?? _ConnectionSide.right,
          );
  }

  Offset get _connectionStartDirection =>
      _connectionSideDirection(_connectionDragSide ?? _ConnectionSide.right);

  _ConnectionSide? get _connectionTargetSide {
    final target = _displayNodes
        .where((node) => node.id == _connectionTargetId)
        .firstOrNull;
    if (target == null) return null;
    return _nearestConnectionSide(
      _connectionScreenRect(target),
      _connectionDragPoint ?? _connectionStartPoint,
    );
  }

  Offset get _connectionEndPoint {
    final target = _displayNodes
        .where((node) => node.id == _connectionTargetId)
        .firstOrNull;
    if (target == null) return _connectionDragPoint ?? _connectionStartPoint;
    final side = _connectionTargetSide!;
    return _connectionAnchor(target, side);
  }

  Offset get _connectionEndDirection {
    final side = _connectionTargetSide;
    if (side != null) return _connectionSideDirection(side) * -1;
    final delta = _connectionEndPoint - _connectionStartPoint;
    return delta.distance == 0
        ? _connectionStartDirection
        : delta / delta.distance;
  }

  void _startConnectionDrag(String id, Offset globalPosition) {
    final local = _canvasLocal(globalPosition);
    final side = _hoveredConnectionNodeId == id
        ? _hoveredConnectionSide ?? _ConnectionSide.right
        : _ConnectionSide.right;
    widget.viewModel.startConnection(id);
    setState(() {
      _connectionDragFrom = id;
      _connectionDragSide = side;
      _connectionDragPoint = local;
      _connectionTargetId = null;
      _hoveredConnectionNodeId = null;
      _hoveredConnectionSide = null;
    });
    // A fast flick can cross the drag threshold only above the target, so the
    // pan-start position must participate in hit testing as well.
    _updateConnectionDrag(globalPosition);
  }

  void _updateConnectionDrag(Offset globalPosition) {
    if (_connectionDragFrom == null) return;
    final local = _canvasLocal(globalPosition);
    final candidates =
        _displayNodes
            .where((node) => node.id != _connectionDragFrom)
            .where((node) => widget.viewModel.canConnectTo(node.id))
            .map(
              (node) =>
                  (node, _distanceToRect(_connectionScreenRect(node), local)),
            )
            .where((candidate) => candidate.$2 <= 40)
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    final target = candidates.firstOrNull?.$1;
    setState(() {
      _connectionDragPoint = local;
      _connectionTargetId = target?.id;
    });
  }

  void _finishConnectionDrag() {
    final target = _connectionTargetId;
    if (target == null) {
      widget.viewModel.cancelConnection();
    } else {
      widget.viewModel.completeConnection(target, cancelOnError: true);
    }
    setState(() {
      _connectionDragFrom = null;
      _connectionDragPoint = null;
      _connectionTargetId = null;
      _hoveredConnectionNodeId = null;
      _hoveredConnectionSide = null;
      _connectionDragSide = null;
    });
  }

  void _cancelConnectionDrag() {
    widget.viewModel.cancelConnection();
    if (!mounted) return;
    setState(() {
      _connectionDragFrom = null;
      _connectionDragPoint = null;
      _connectionTargetId = null;
      _connectionDragSide = null;
    });
  }

  Offset _canvasLocal(Offset globalPosition) {
    final box = _canvasKey.currentContext!.findRenderObject()! as RenderBox;
    return box.globalToLocal(globalPosition);
  }

  /// Screen-space annotation layer: constant-size markers on commented cards
  /// and arrows, and the thread popover anchored beside the open marker.
  /// Rendered outside the world transform so it stays readable at any zoom.
  List<Widget> _commentLayer(Rect visible, Size viewport) {
    final vm = widget.viewModel;
    final pending = vm.pendingRequestTargetIds;
    if (pending.isEmpty) {
      if (_commentAnchor != null) {
        // The last pending request was resolved or removed while open.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _commentAnchor != null) {
            setState(() {
              _commentAnchor = null;
              _commentAnchorIds = const {};
            });
          }
        });
      }
      return const [];
    }
    const markerSize = 26.0;
    final anchors = <String, (Offset, Set<String>)>{};
    for (final node in _displayNodes) {
      if (!pending.contains(node.id)) continue;
      final rect = node.position & nodeSize;
      if (!visible.overlaps(rect)) continue;
      anchors[node.id] = (_camera.worldToScreen(rect.topRight), {node.id});
    }
    for (final route in _routes) {
      final ids = {route.edge.id, ...?vm.levelGraph.edgeSources[route.edge.id]};
      if (!ids.any(pending.contains)) continue;
      final metric = route.metric;
      final mid = metric?.getTangentForOffset(metric.length / 2)?.position;
      if (mid == null || !visible.contains(mid)) continue;
      anchors['edge:${route.edge.id}'] = (_camera.worldToScreen(mid), ids);
    }
    final children = <Widget>[
      for (final entry in anchors.entries)
        Positioned(
          left: entry.value.$1.dx - markerSize / 2,
          top: entry.value.$1.dy - markerSize / 2,
          child: _CommentMarker(
            key: ValueKey('comment-marker-${entry.key}'),
            count: vm.pendingRequestsFor(entry.value.$2).length,
            onTap: () => setState(() {
              _commentAnchor = entry.key;
              _commentAnchorIds = entry.value.$2;
            }),
          ),
        ),
    ];
    final anchor = _commentAnchor == null ? null : anchors[_commentAnchor];
    if (anchor != null) {
      final items = vm.pendingRequestsFor(_commentAnchorIds);
      if (items.isNotEmpty) {
        const width = 300.0;
        final left = (anchor.$1.dx + markerSize / 2 + 6)
            .clamp(8.0, math.max(8.0, viewport.width - width - 8))
            .toDouble();
        final top = (anchor.$1.dy - 8)
            .clamp(8.0, math.max(8.0, viewport.height - 160))
            .toDouble();
        children.add(
          Positioned(
            left: left,
            top: top,
            child: _CommentPopover(
              key: _popoverKey,
              items: items,
              maxHeight: math.min(280, viewport.height - top - 12),
              onOpenList: () {
                setState(() {
                  _commentAnchor = null;
                  _commentAnchorIds = const {};
                });
                widget.onOpenComments?.call();
              },
              onClose: () => setState(() {
                _commentAnchor = null;
                _commentAnchorIds = const {};
              }),
            ),
          ),
        );
      }
    }
    return children;
  }

  Widget _worldWidget(
    Rect worldRect,
    Widget child, {
    required String nodeId,
    bool draftTarget = false,
  }) {
    final screen = _camera.worldToScreen(worldRect.topLeft);
    return Positioned(
      key: ValueKey<Key?>(child.key),
      left: screen.dx,
      top: screen.dy,
      child: Transform.scale(
        scale: _camera.scale,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: worldRect.width,
          height: worldRect.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: AgentPulse(
                  radius:
                      widget.viewModel.levelGraph.processIds.contains(nodeId)
                      ? AppTheme.radiusProcessCard
                      : AppTheme.radiusCard,
                  active: widget.viewModel.agentChangedIds.contains(nodeId),
                  version: widget.viewModel.agentChangeVersion,
                  child: child,
                ),
              ),
              // The draft's anchor: an offset ring, distinct from the
              // selection border, that survives selection changes.
              if (draftTarget)
                Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
                  bottom: -5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: ValueKey('comment-draft-ring-$nodeId'),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: context.colors.accent.withValues(alpha: .7),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(
                          (widget.viewModel.levelGraph.processIds.contains(
                                    nodeId,
                                  )
                                  ? AppTheme.radiusProcessCard
                                  : AppTheme.radiusCard) +
                              5,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _worldFromGlobal(Offset globalPosition) {
    final box = _canvasKey.currentContext!.findRenderObject()! as RenderBox;
    return _camera.screenToWorld(box.globalToLocal(globalPosition));
  }

  void _startNodeDrag(ArchitectureNode node, Offset globalPosition) {
    if (!widget.viewModel.canEdit || !WriteAccessScope.canWriteOf(context)) {
      return;
    }
    if (widget.viewModel.canvasTool != CanvasTool.select ||
        HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.space,
        )) {
      return;
    }
    final vm = widget.viewModel;
    final keyboard = HardwareKeyboard.instance;
    _dragAdditive =
        keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed;
    _dragSelectionPrepared = vm.isCardSelected(node.id);
    _dragNodeId = node.id;
    widget.viewModel.repository.beginTransaction();
    _dragStartWorld = _worldFromGlobal(globalPosition);
    final visible = {for (final item in _displayNodes) item.id: item.position};
    final dragIds = {
      if (_dragAdditive || _dragSelectionPrepared) ...vm.selectedCardIds,
      node.id,
    };
    _dragStartPositions = {
      for (final entry in visible.entries)
        if (dragIds.contains(entry.key)) entry.key: entry.value,
    };
    _dragPositions = _dragStartPositions;
    if (_frontNodeId != node.id) {
      setState(() => _frontNodeId = node.id);
    }
    if (_arrangeAnimation.isAnimating) {
      _stopArrange();
      widget.viewModel.setNodePosition(node.id, node.position);
    }
  }

  void _updateNodeDrag(String id, Offset globalPosition) {
    if (_dragNodeId != id || _dragStartWorld == null) return;
    if (!_dragSelectionPrepared) {
      widget.viewModel.selectCards([id], additive: _dragAdditive);
      _dragSelectionPrepared = true;
    }
    final delta = _worldFromGlobal(globalPosition) - _dragStartWorld!;
    setState(() {
      _dragPositions = {
        for (final entry in _dragStartPositions.entries)
          entry.key: entry.value + delta,
      };
    });
  }

  void _endNodeDrag() {
    final positions = _dragPositions;
    final changed = positions.entries.any(
      (entry) => _dragStartPositions[entry.key] != entry.value,
    );
    _dragNodeId = null;
    _dragStartWorld = null;
    _dragStartPositions = const {};
    _dragPositions = const {};
    _dragSelectionPrepared = false;
    if (changed) widget.viewModel.setCardPositions(positions);
    widget.viewModel.repository.endTransaction();
  }
}

class _ConnectionDragPainter extends CustomPainter {
  const _ConnectionDragPainter({
    required this.start,
    required this.end,
    required this.startDirection,
    required this.endDirection,
    required this.color,
  });

  final Offset start;
  final Offset end;
  final Offset startDirection;
  final Offset endDirection;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final reach = math.max(52.0, (end - start).distance * .42);
    final first = start + startDirection * reach;
    final second = end - endDirection * reach;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(first.dx, first.dy, second.dx, second.dy, end.dx, end.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    final tangent = math.atan2(end.dy - second.dy, end.dx - second.dx);
    canvas.drawPath(
      connectionArrowHead(end, tangent, 1),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ConnectionDragPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.startDirection != startDirection ||
      oldDelegate.endDirection != endDirection ||
      oldDelegate.color != color;
}

class _ViewportPainter extends CustomPainter {
  _ViewportPainter({
    required this.showGrid,
    required this.palette,
    required this.camera,
    required this.nodes,
    required this.routes,
    required this.selectedNodeId,
    required this.selectedEdgeId,
    required this.ignition,
  }) : super(repaint: ignition);
  final AppPalette palette;
  final bool showGrid;
  final CanvasCamera camera;
  final List<ArchitectureNode> nodes;
  final List<EdgeRoute> routes;
  final String? selectedNodeId;
  final String? selectedEdgeId;
  final Animation<double> ignition;
  double get ignitionProgress =>
      AppTheme.edgeIgnitionCurve.transform(ignition.value);

  @override
  void paint(Canvas canvas, Size size) {
    if (showGrid) _drawGrid(canvas, size);
    _drawSystemEdges(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    var spacing = 24 * camera.scale;
    while (spacing < 16) {
      spacing *= 4;
    }
    final origin = camera.translation;
    final startX = origin.dx % spacing;
    final startY = origin.dy % spacing;
    final paint = Paint()..color = palette.line.withValues(alpha: .42);
    for (double x = startX; x < size.width; x += spacing) {
      for (double y = startY; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), .7, paint);
      }
    }
  }

  void _drawSystemEdges(Canvas canvas) {
    final visible = camera.visibleWorldRect.inflate(260 / camera.scale);
    for (final route in routes) {
      if (!visible.overlaps(route.bounds.inflate(12))) continue;
      final edge = route.edge;
      final selected = selectedEdgeId == edge.id;
      final related =
          selectedEdgeId == null &&
          selectedNodeId != null &&
          (edge.from == selectedNodeId || edge.to == selectedNodeId);
      final progress = related ? ignitionProgress : 1.0;
      final travelling = related && progress < 1;
      final paint = Paint()
        ..color = selected
            ? palette.accent
            : related && !travelling
            ? palette.edge
            : palette.edgeMuted
        ..strokeWidth =
            (selected ? AppTheme.arrowSelectedStroke : AppTheme.arrowStroke) /
            camera.scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.save();
      canvas.translate(camera.translation.dx, camera.translation.dy);
      canvas.scale(camera.scale);
      canvas.drawPath(route.path, paint);
      if (travelling && progress > 0) {
        final metric = route.metric;
        if (metric != null && metric.length > 0) {
          final end = metric.length * progress;
          final litPaint = Paint()
            ..color = palette.edge
            ..strokeWidth = paint.strokeWidth
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke;
          canvas.drawPath(metric.extractPath(0, end), litPaint);
          // A short leading glint follows path distance, not screen X/Y.
          canvas.drawPath(
            metric.extractPath(math.max(0, end - 22 / camera.scale), end),
            litPaint
              ..color = palette.accent.withValues(
                alpha: math.sin(math.pi * progress) * .8,
              ),
          );
        }
      }
      canvas.restore();
      _drawArrow(
        canvas,
        camera.worldToScreen(route.tip),
        route.angle,
        travelling
            ? Color.lerp(
                palette.edgeMuted,
                palette.edge,
                ((progress - .94) / .06).clamp(0.0, 1.0),
              )!
            : paint.color,
        selected,
      );
    }
  }

  void _drawArrow(
    Canvas canvas,
    Offset end,
    double tangent,
    Color color,
    bool selected,
  ) {
    canvas.drawPath(
      connectionArrowHead(end, tangent, camera.scale),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewportPainter oldDelegate) =>
      oldDelegate.showGrid != showGrid ||
      oldDelegate.palette != palette ||
      oldDelegate.camera.scale != camera.scale ||
      oldDelegate.camera.translation != camera.translation ||
      oldDelegate.camera.viewport != camera.viewport ||
      !identical(oldDelegate.routes, routes) ||
      oldDelegate.selectedNodeId != selectedNodeId ||
      oldDelegate.selectedEdgeId != selectedEdgeId;
}

class _NodeCard extends StatefulWidget {
  const _NodeCard({
    super.key,
    required this.node,
    required this.selected,
    required this.connecting,
    required this.connectionTarget,
    required this.invalidConnectionTarget,
    required this.onTap,
    required this.onFocus,
    required this.onNudge,
    required this.onActivate,
    required this.activationEnabled,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onOpen,
    this.footer,
    this.reference = false,
    this.referenceFlow,
    this.process = false,
  });
  final ArchitectureNode node;
  final VoidCallback? onOpen;
  final String? footer;
  final bool reference;
  final ReferenceFlow? referenceFlow;
  final bool process;
  final bool selected;
  final bool connecting;
  final bool connectionTarget;
  final bool invalidConnectionTarget;
  final VoidCallback onTap;
  final VoidCallback onFocus;
  final ValueChanged<Offset>? onNudge;
  final VoidCallback onActivate;
  final bool activationEnabled;
  final ValueChanged<Offset> onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  @override
  State<_NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<_NodeCard> {
  bool _keyboardFocused = false;
  final Stopwatch _semanticTapClock = Stopwatch()..start();
  Duration? _lastTap;
  bool? _lastTapWasPointer;
  Offset? _lastTapPosition;
  PointerDownEvent? _pointerDown;

  void _tap() {
    final down = _pointerDown;
    _pointerDown = null;
    final wasPointer = down != null;
    final now = down?.timeStamp ?? _semanticTapClock.elapsed;
    final elapsed = _lastTap == null || _lastTapWasPointer != wasPointer
        ? null
        : now - _lastTap!;
    final activate =
        widget.activationEnabled &&
        elapsed != null &&
        !elapsed.isNegative &&
        elapsed <= kDoubleTapTimeout &&
        (down == null ||
            _lastTapPosition == null ||
            (down.position - _lastTapPosition!).distance <= kDoubleTapSlop);
    // Pointer timestamps keep physical clicks deterministic. Accessibility
    // sends semantic taps without PointerDown, so use a monotonic fallback for
    // that path. Selection stays immediate in both cases.
    _lastTap = widget.activationEnabled && !activate ? now : null;
    _lastTapWasPointer = widget.activationEnabled && !activate
        ? wasPointer
        : null;
    _lastTapPosition = widget.activationEnabled && !activate
        ? down?.position
        : null;
    if (activate) {
      widget.onActivate();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) {
      setState(() => _keyboardFocused = focused);
      if (focused) widget.onFocus();
    },
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        widget.activationEnabled ? widget.onActivate() : widget.onTap();
        return KeyEventResult.handled;
      }
      if (!widget.activationEnabled ||
          widget.reference ||
          widget.onNudge == null) {
        return KeyEventResult.ignored;
      }
      final delta = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
        LogicalKeyboardKey.arrowRight => const Offset(1, 0),
        LogicalKeyboardKey.arrowUp => const Offset(0, -1),
        LogicalKeyboardKey.arrowDown => const Offset(0, 1),
        _ => null,
      };
      if (delta == null) return KeyEventResult.ignored;
      widget.onNudge!(
        delta * (HardwareKeyboard.instance.isShiftPressed ? 40 : 10),
      );
      return KeyEventResult.handled;
    },
    child: Semantics(
      button: true,
      selected: widget.selected,
      label: widget.node.title,
      child: Listener(
        onPointerDown: (event) => _pointerDown = event,
        child: _buildCard(context),
      ),
    ),
  );

  Widget _buildCard(BuildContext context) {
    final node = widget.node;
    final selected = widget.selected || _keyboardFocused;
    final connecting = widget.connecting;
    final connectionTarget = widget.connectionTarget;
    final invalidConnectionTarget = widget.invalidConnectionTarget;
    final reference = widget.reference;
    final footer = widget.footer;
    final onOpen = widget.onOpen;
    return GestureDetector(
      onTap: _tap,
      onPanDown: (d) => widget.onDragStart(d.globalPosition),
      onPanUpdate: (d) {
        _lastTap = null;
        widget.onDragUpdate(d.globalPosition);
      },
      onPanEnd: (_) => widget.onDragEnd(),
      onPanCancel: widget.onDragEnd,
      child: _portal(
        Container(
          padding: reference ? EdgeInsets.zero : const EdgeInsets.all(16),
          decoration: reference
              ? AppTheme.referenceCard(
                  context,
                  active: selected || connecting || connectionTarget,
                )
              : BoxDecoration(
                  color: widget.process
                      ? Colors.transparent
                      : selected || connecting || connectionTarget
                      ? context.colors.surfaceHigh
                      : context.colors.surface,
                  borderRadius: BorderRadius.circular(
                    widget.process
                        ? AppTheme.radiusProcessCard
                        : AppTheme.radiusCard,
                  ),
                  border: Border.all(
                    color: invalidConnectionTarget
                        ? context.colors.danger
                        : selected || connecting
                        ? context.colors.accent
                        : connectionTarget
                        ? context.colors.accent.withValues(alpha: .55)
                        : context.colors.line,
                    width: selected || connecting || invalidConnectionTarget
                        ? 1.5
                        : 1,
                  ),
                ),
          child: reference
              ? _referenceContent(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The same fallback the selection bar and search use,
                      // and it must match the card's type.
                      node.title.isEmpty
                          ? (widget.process
                                ? context.l10n.newFold
                                : context.l10n.newBlock)
                          : node.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        node.description,
                        maxLines: footer == null ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.bodySmall!.copyWith(
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                    if (footer != null)
                      SizedBox(
                        height: 22,
                        child: InkWell(
                          key: ValueKey('enter-${node.id}'),
                          onTap: onOpen,
                          child: Row(
                            children: [
                              Icon(
                                Icons.subdirectory_arrow_right,
                                size: 14,
                                color: context.colors.accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  footer,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.type.labelSmall!.copyWith(
                                    color: context.colors.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _referenceContent(BuildContext context) {
    final flow = widget.referenceFlow ?? ReferenceFlow.outside;
    final label = switch (flow) {
      ReferenceFlow.input => context.l10n.referenceInput,
      ReferenceFlow.output => context.l10n.referenceOutput,
      ReferenceFlow.both => context.l10n.referenceBoth,
      ReferenceFlow.outside => context.l10n.outside,
    };
    final icon = switch (flow) {
      ReferenceFlow.input => Icons.login_rounded,
      ReferenceFlow.output => Icons.logout_rounded,
      ReferenceFlow.both => Icons.swap_horiz_rounded,
      ReferenceFlow.outside => Icons.open_in_new_rounded,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.node.title.isEmpty
                      ? (widget.process
                            ? context.l10n.newFold
                            : context.l10n.newBlock)
                      : widget.node.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.titleMedium,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    widget.node.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodySmall!.copyWith(
                      color: context.colors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Tooltip(
          message: widget.footer ?? context.l10n.outside,
          child: InkWell(
            key: ValueKey('enter-${widget.node.id}'),
            onTap: widget.onOpen,
            child: Container(
              height: 30,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: context.colors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.footer == context.l10n.thisFold
                          ? widget.footer!
                          : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.labelSmall!.copyWith(
                        color: context.colors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 13,
                    color: context.colors.accent,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _portal(Widget child) => widget.process
      ? ProcessPortal(key: ValueKey('portal-${widget.node.id}'), child: child)
      : widget.reference
      ? ReferencePortal(
          key: ValueKey('reference-portal-${widget.node.id}'),
          child: child,
        )
      : child;
}

class _CanvasControls extends StatelessWidget {
  const _CanvasControls({
    super.key,
    this.compact = false,
    required this.scale,
    required this.canArrange,
    required this.onTidy,
    required this.onRebuild,
    required this.onMinus,
    required this.onPlus,
    required this.onFit,
  });
  final double scale;
  final bool compact;
  final bool canArrange;
  final VoidCallback onTidy;
  final VoidCallback onRebuild;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onFit;
  @override
  Widget build(BuildContext context) => compact
      ? Container(
          key: const Key('zoom-controls'),
          width: 64,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: context.colors.line),
          ),
          child: PopupMenuButton<String>(
            key: const Key('zoom-menu'),
            tooltip: context.l10n.canvasControls,
            onSelected: (value) {
              switch (value) {
                case 'tidy':
                  onTidy();
                case 'rebuild':
                  onRebuild();
                case 'in':
                  onPlus();
                case 'out':
                  onMinus();
                case 'fit':
                  onFit();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const Key('arrange-board'),
                value: 'tidy',
                enabled: canArrange,
                child: Text(context.l10n.arrange),
              ),
              PopupMenuItem(
                key: const Key('rebuild-board'),
                value: 'rebuild',
                enabled: canArrange,
                child: Text(context.l10n.rebuildLayout),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'in', child: Text(context.l10n.zoomIn)),
              PopupMenuItem(value: 'out', child: Text(context.l10n.zoomOut)),
              PopupMenuItem(value: 'fit', child: Text(context.l10n.fitContent)),
            ],
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.zoomPercent((scale * 100).round()),
                    style: context.type.labelSmall,
                  ),
                  const Icon(Icons.expand_more, size: 14),
                ],
              ),
            ),
          ),
        )
      : Container(
          key: const Key('zoom-controls'),
          height: 38,
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            border: Border.all(color: context.colors.line),
          ),
          child: Row(
            children: [
              IconButton(
                key: const Key('arrange-board'),
                onPressed: canArrange ? onTidy : null,
                tooltip: context.l10n.arrange,
                icon: const Icon(Icons.auto_fix_high_outlined, size: 17),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                key: const Key('rebuild-board'),
                onPressed: canArrange ? onRebuild : null,
                tooltip: context.l10n.rebuildLayout,
                // Not account_tree: that glyph names the fold type in the
                // inspector, and one glyph cannot mean two things.
                icon: const Icon(Icons.schema_outlined, size: 17),
                visualDensity: VisualDensity.compact,
              ),
              Container(height: 20, width: 1, color: context.colors.line),
              IconButton(
                onPressed: onMinus,
                tooltip: context.l10n.zoomOut,
                icon: const Icon(Icons.remove, size: 15),
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(
                width: 38,
                child: Text(
                  context.l10n.zoomPercent((scale * 100).round()),
                  textAlign: TextAlign.center,
                  style: AppTheme.zoomLabel.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ),
              IconButton(
                onPressed: onPlus,
                tooltip: context.l10n.zoomIn,
                icon: const Icon(Icons.add, size: 15),
                visualDensity: VisualDensity.compact,
              ),
              Container(height: 20, width: 1, color: context.colors.line),
              IconButton(
                onPressed: onFit,
                tooltip: context.l10n.fitContent,
                icon: const Icon(Icons.fit_screen_outlined, size: 15),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        );
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({
    super.key,
    required this.camera,
    required this.bounds,
    required this.nodes,
  });
  final CanvasCamera camera;
  final Rect bounds;
  final List<ArchitectureNode> nodes;
  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    height: 96,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: context.colors.surface.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: context.colors.line),
    ),
    child: Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _MiniMapNodesPainter(
              palette: context.colors,
              bounds: bounds,
              nodes: nodes,
            ),
          ),
        ),
        CustomPaint(
          painter: _MiniMapViewportPainter(
            palette: context.colors,
            camera: camera,
            bounds: bounds,
          ),
        ),
      ],
    ),
  );
}

class _MiniMapNodesPainter extends CustomPainter {
  _MiniMapNodesPainter({
    required this.palette,
    required this.bounds,
    required this.nodes,
  });
  final AppPalette palette;
  final Rect bounds;
  final List<ArchitectureNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final safe = bounds.inflate(80);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final scale = math.min(size.width / safe.width, size.height / safe.height);
    Offset map(Offset p) =>
        Offset((p.dx - safe.left) * scale, (p.dy - safe.top) * scale);
    final itemPaint = Paint()..color = palette.accent.withValues(alpha: .68);
    for (final node in nodes) {
      final p = map(node.position);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(p.dx, p.dy, 260 * scale, 118 * scale),
          const Radius.circular(1),
        ),
        itemPaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniMapNodesPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.bounds != bounds ||
      !identical(oldDelegate.nodes, nodes);
}

class _MiniMapViewportPainter extends CustomPainter {
  _MiniMapViewportPainter({
    required this.palette,
    required this.camera,
    required this.bounds,
  });
  final AppPalette palette;
  final CanvasCamera camera;
  final Rect bounds;

  @override
  void paint(Canvas canvas, Size size) {
    final safe = bounds.inflate(80);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final scale = math.min(size.width / safe.width, size.height / safe.height);
    Offset map(Offset p) =>
        Offset((p.dx - safe.left) * scale, (p.dy - safe.top) * scale);
    final visible = camera.visibleWorldRect;
    final vp = map(visible.topLeft);
    canvas.drawRect(
      Rect.fromLTWH(
        vp.dx,
        vp.dy,
        visible.width * scale,
        visible.height * scale,
      ),
      Paint()..color = palette.text.withValues(alpha: .07),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        vp.dx,
        vp.dy,
        visible.width * scale,
        visible.height * scale,
      ),
      Paint()
        ..color = palette.text.withValues(alpha: .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniMapViewportPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.bounds != bounds ||
      oldDelegate.camera.scale != camera.scale ||
      oldDelegate.camera.translation != camera.translation ||
      oldDelegate.camera.viewport != camera.viewport;
}

/// A constant-size pin: pending human requests target this card or arrow.
/// Tapping opens the thread beside the pin; it never edits the board.
class _CommentMarker extends StatelessWidget {
  const _CommentMarker({super.key, this.onTap, this.count = 1});
  final VoidCallback? onTap;
  final int count;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: context.l10n.pendingCommentMarker,
    child: Material(
      color: context.colors.accentDark,
      elevation: 2,
      shape: CircleBorder(side: BorderSide(color: context.colors.accent)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: count > 1
              ? Center(
                  child: Text(
                    '$count',
                    style: context.type.labelSmall!.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                )
              : Icon(
                  Icons.chat_bubble_outline,
                  size: 13,
                  color: context.colors.accent,
                ),
        ),
      ),
    ),
  );
}

/// The thread, in place: pending requests for one anchor, read where the
/// object is. Resolved requests leave the canvas and live in the list.
class _CommentPopover extends StatelessWidget {
  const _CommentPopover({
    super.key,
    required this.items,
    required this.maxHeight,
    required this.onOpenList,
    required this.onClose,
  });
  final List<BoardRequest> items;
  final double maxHeight;
  final VoidCallback onOpenList;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const Key('comment-popover'),
    decoration: AppTheme.floatingPanel(context),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusFloating),
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 300,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(120, maxHeight)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: context.colors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.pendingRequests(items.length),
                          style: context.type.labelMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('close-comment-popover'),
                        tooltip: context.l10n.close,
                        visualDensity: VisualDensity.compact,
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    itemBuilder: (_, index) => SelectableText(
                      items[index].text,
                      style: context.type.bodySmall,
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                    child: TextButton.icon(
                      key: const Key('open-requests-list'),
                      onPressed: onOpenList,
                      icon: const Icon(Icons.list_alt_outlined, size: 16),
                      label: Text(context.l10n.agentRequests),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
