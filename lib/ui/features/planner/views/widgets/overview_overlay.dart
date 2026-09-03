import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../../domain/models/architecture_models.dart';
import '../../../../../domain/use_cases/auto_layout_architecture.dart';
import '../../../../core/app_theme.dart';
import '../../view_models/planner_view_model.dart';

class OverviewOverlay extends StatelessWidget {
  const OverviewOverlay({
    super.key,
    required this.viewModel,
    required this.onClose,
    required this.onOpenLevel,
  });

  final PlannerViewModel viewModel;
  final VoidCallback onClose;
  final ValueChanged<String?> onOpenLevel;

  @override
  Widget build(BuildContext context) {
    final empty = viewModel.nodes.isEmpty;
    final directEdges = _flattenEdges(
      viewModel.nodes,
      viewModel.groups,
      viewModel.edges,
    );
    return Material(
      key: const Key('overview-layer'),
      color: context.colors.background,
      child: Column(
        children: [
          _OverviewBar(
            blocks: viewModel.nodes.length,
            connections: directEdges.length,
            showRoot: viewModel.currentLevelId != null,
            onOpenRoot: () => onOpenLevel(null),
            onClose: onClose,
          ),
          Expanded(
            child: empty
                ? const _EmptyOverview()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          border: Border.all(color: context.colors.line),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusCard,
                          ),
                        ),
                        child: _FlatBoardMap(
                          nodes: viewModel.nodes,
                          groups: viewModel.groups,
                          edges: directEdges,
                        ),
                      ),
                    ),
                  ),
          ),
          if (!empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                context.l10n.overviewHint,
                textAlign: TextAlign.center,
                style: context.type.bodySmall!.copyWith(
                  color: context.colors.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewBar extends StatelessWidget {
  const _OverviewBar({
    required this.blocks,
    required this.connections,
    required this.showRoot,
    required this.onOpenRoot,
    required this.onClose,
  });

  final int blocks;
  final int connections;
  final bool showRoot;
  final VoidCallback onOpenRoot;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(bottom: BorderSide(color: context.colors.line)),
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: context.colors.accentDark,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          ),
          child: Icon(
            Icons.map_outlined,
            size: 19,
            color: context.colors.accent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.overview, style: context.type.titleMedium),
              Text(
                context.l10n.overviewStats(blocks, connections),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.bodySmall!.copyWith(
                  color: context.colors.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        if (showRoot)
          IconButton(
            key: const Key('overview-open-root'),
            tooltip: context.l10n.rootLevel,
            onPressed: onOpenRoot,
            icon: const Icon(Icons.home_outlined, size: 19),
          ),
        if (MediaQuery.sizeOf(context).width >= 480)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.line),
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: context.colors.muted,
                ),
                const SizedBox(width: 5),
                Text(
                  context.l10n.overviewReadOnly,
                  style: context.type.labelSmall!.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 4),
        IconButton(
          key: const Key('close-overview'),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: onClose,
          icon: const Icon(Icons.close, size: 20),
        ),
      ],
    ),
  );
}

class _EmptyOverview extends StatelessWidget {
  const _EmptyOverview();

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 30, color: context.colors.muted),
            const SizedBox(height: 14),
            Text(
              context.l10n.overviewEmptyTitle,
              textAlign: TextAlign.center,
              style: context.type.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.overviewEmptyHint,
              textAlign: TextAlign.center,
              style: context.type.bodyMedium!.copyWith(
                color: context.colors.muted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FlatBoardMap extends StatefulWidget {
  const _FlatBoardMap({
    required this.nodes,
    required this.groups,
    required this.edges,
  });

  final List<ArchitectureNode> nodes;
  final List<ArchitectureGroup> groups;
  final List<ArchitectureEdge> edges;

  @override
  State<_FlatBoardMap> createState() => _FlatBoardMapState();
}

class _FlatBoardMapState extends State<_FlatBoardMap> {
  static const _minScale = .002;
  final TransformationController _controller = TransformationController();
  late _FlatMapLayout _layout;
  String? _fitSignature;

  @override
  void initState() {
    super.initState();
    _layout = _FlatMapLayout.build(widget.nodes, widget.groups, widget.edges);
  }

  @override
  void didUpdateWidget(covariant _FlatBoardMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.nodes, widget.nodes) ||
        !identical(oldWidget.groups, widget.groups) ||
        !identical(oldWidget.edges, widget.edges)) {
      _layout = _FlatMapLayout.build(widget.nodes, widget.groups, widget.edges);
      _fitSignature = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fit(Size viewport) {
    if (!mounted || viewport.isEmpty) return;
    final scale =
        (math.min(
                  viewport.width / _layout.size.width,
                  viewport.height / _layout.size.height,
                ) *
                .9)
            .clamp(_minScale, 1.0);
    final dx = (viewport.width - _layout.size.width * scale) / 2;
    final dy = (viewport.height - _layout.size.height * scale) / 2;
    _controller.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      final layout = _layout;
      final signature =
          '${layout.size.width}:${layout.size.height}:'
          '${viewport.width}:${viewport.height}';
      if (_fitSignature != signature) {
        _fitSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fit(viewport);
        });
      }
      return Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              key: const Key('overview-map'),
              transformationController: _controller,
              constrained: false,
              minScale: _minScale,
              maxScale: 5,
              boundaryMargin: const EdgeInsets.all(double.infinity),
              child: SizedBox.fromSize(
                size: layout.size,
                child: IgnorePointer(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: true,
                    painter: _FlatMapPainter(
                      layout: layout,
                      controller: _controller,
                      viewport: viewport,
                      surface: context.colors.surfaceHigh,
                      line: context.colors.line,
                      text: context.colors.text,
                      muted: context.colors.muted,
                      edge: context.colors.edge,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: context.colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                side: BorderSide(color: context.colors.line),
              ),
              child: IconButton(
                key: const Key('overview-fit-all'),
                tooltip: context.l10n.fitContent,
                onPressed: () => _fit(viewport),
                icon: const Icon(Icons.fit_screen_outlined, size: 19),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _FlatMapLayout {
  const _FlatMapLayout({
    required this.size,
    required this.nodes,
    required this.edges,
    required this.edgeVisuals,
  });

  static const nodeSize = Size(260, 118);
  final Size size;
  final List<ArchitectureNode> nodes;
  final List<ArchitectureEdge> edges;
  final List<_MapEdgeVisual> edgeVisuals;

  static _FlatMapLayout build(
    List<ArchitectureNode> sourceNodes,
    List<ArchitectureGroup> groups,
    List<ArchitectureEdge> edges,
  ) {
    final groupsById = {for (final group in groups) group.id: group};
    String? topLevel(String? parentId) {
      var group = groupsById[parentId];
      if (group == null) return null;
      final seen = <String>{};
      while (group!.parentId != null && seen.add(group.id)) {
        final parent = groupsById[group.parentId];
        if (parent == null) break;
        group = parent;
      }
      return group.id;
    }

    final buckets = <String?, List<ArchitectureNode>>{};
    for (final node in sourceNodes) {
      buckets.putIfAbsent(topLevel(node.parentId), () => []).add(node);
    }
    final clusters = <_MapCluster>[];
    for (final entry in buckets.entries) {
      final ids = entry.value.map((node) => node.id).toSet();
      final clusterEdges = [
        for (final edge in edges)
          if (ids.contains(edge.from) && ids.contains(edge.to)) edge,
      ];
      final flatNodes = [
        for (final node in entry.value) node.copyWith(clearParent: true),
      ];
      final positions = const AutoLayoutArchitecture()(
        nodes: flatNodes,
        edges: clusterEdges,
        groups: const [],
      ).nodePositions;
      var arranged = [
        for (final node in flatNodes)
          node.copyWith(position: positions[node.id] ?? node.position),
      ];
      var bounds = arranged
          .map((node) => node.position & nodeSize)
          .reduce((a, b) => a.expandToInclude(b));

      // A cyclic or disconnected cluster can collapse into one very tall
      // rank. Repack only that pathological case; normal graph layers retain
      // their direction and neighbour ordering.
      final aspect = bounds.width / math.max(1, bounds.height);
      if (aspect < .38 || aspect > 3.8) {
        arranged.sort((a, b) {
          final aPosition = positions[a.id] ?? a.position;
          final bPosition = positions[b.id] ?? b.position;
          final column = aPosition.dx.compareTo(bPosition.dx);
          return column != 0 ? column : aPosition.dy.compareTo(bPosition.dy);
        });
        const columnStep = 420.0;
        const rowStep = 174.0;
        final columns = math.max(
          1,
          math.sqrt(arranged.length * 1.45 * rowStep / columnStep).ceil(),
        );
        final rows = (arranged.length / columns).ceil();
        arranged = [
          for (var index = 0; index < arranged.length; index++)
            arranged[index].copyWith(
              position: Offset(
                (index ~/ rows) * columnStep,
                (index % rows) * rowStep,
              ),
            ),
        ];
        bounds = arranged
            .map((node) => node.position & nodeSize)
            .reduce((a, b) => a.expandToInclude(b));
      }
      final shift = -bounds.topLeft;
      clusters.add(
        _MapCluster(
          id: entry.key,
          size: bounds.size,
          nodes: [
            for (final node in arranged)
              node.copyWith(position: node.position + shift),
          ],
        ),
      );
    }
    clusters.sort((a, b) {
      if (a.id == null) return -1;
      if (b.id == null) return 1;
      return a.id!.compareTo(b.id!);
    });

    const margin = 80.0;
    const gap = 160.0;
    final totalArea = clusters.fold<double>(
      0,
      (sum, cluster) =>
          sum + (cluster.size.width + gap) * (cluster.size.height + gap),
    );
    final targetWidth = math.sqrt(totalArea * 1.55).clamp(1200.0, 9000.0);
    final arranged = <ArchitectureNode>[];
    var x = margin;
    var y = margin;
    var rowHeight = 0.0;
    var right = margin;
    for (final cluster in clusters) {
      if (x > margin && x + cluster.size.width > targetWidth) {
        x = margin;
        y += rowHeight + gap;
        rowHeight = 0;
      }
      final offset = Offset(x, y);
      arranged.addAll([
        for (final node in cluster.nodes)
          node.copyWith(position: node.position + offset),
      ]);
      right = math.max(right, x + cluster.size.width);
      rowHeight = math.max(rowHeight, cluster.size.height);
      x += cluster.size.width + gap;
    }
    final byId = {for (final node in arranged) node.id: node};
    final edgeVisuals = <_MapEdgeVisual>[];
    for (final connection in edges) {
      final from = byId[connection.from];
      final to = byId[connection.to];
      if (from == null || to == null || from.id == to.id) continue;
      final fromRect = from.position & nodeSize;
      final toRect = to.position & nodeSize;
      final rightward = toRect.center.dx >= fromRect.center.dx;
      final start = Offset(
        rightward ? fromRect.right : fromRect.left,
        fromRect.center.dy,
      );
      final end = Offset(
        rightward ? toRect.left : toRect.right,
        toRect.center.dy,
      );
      final reach = (end.dx - start.dx) * .42;
      final control = Offset(end.dx - reach, end.dy);
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(
          start.dx + reach,
          start.dy,
          control.dx,
          control.dy,
          end.dx,
          end.dy,
        );
      final angle = (end - control).direction;
      const arrow = 10.0;
      final arrowPath = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - arrow * math.cos(angle - .45),
          end.dy - arrow * math.sin(angle - .45),
        )
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - arrow * math.cos(angle + .45),
          end.dy - arrow * math.sin(angle + .45),
        );
      edgeVisuals.add(
        _MapEdgeVisual(
          path: path,
          arrow: arrowPath,
          bounds: fromRect.expandToInclude(toRect),
        ),
      );
    }
    return _FlatMapLayout(
      size: Size(right + margin, y + rowHeight + margin),
      nodes: List.unmodifiable(arranged),
      edges: List.unmodifiable(edges),
      edgeVisuals: List.unmodifiable(edgeVisuals),
    );
  }
}

class _MapEdgeVisual {
  const _MapEdgeVisual({
    required this.path,
    required this.arrow,
    required this.bounds,
  });

  final Path path;
  final Path arrow;
  final Rect bounds;
}

class _MapCluster {
  const _MapCluster({
    required this.id,
    required this.size,
    required this.nodes,
  });

  final String? id;
  final Size size;
  final List<ArchitectureNode> nodes;
}

class _FlatMapPainter extends CustomPainter {
  _FlatMapPainter({
    required this.layout,
    required this.controller,
    required this.viewport,
    required this.surface,
    required this.line,
    required this.text,
    required this.muted,
    required this.edge,
  }) : super(repaint: controller);

  final _FlatMapLayout layout;
  final TransformationController controller;
  final Size viewport;
  final Color surface;
  final Color line;
  final Color text;
  final Color muted;
  final Color edge;
  final Map<String, TextPainter> _titles = {};
  final Map<String, TextPainter> _descriptions = {};

  @override
  void paint(Canvas canvas, Size size) {
    final transform = controller.value;
    final scale = math.max(.001, transform.getMaxScaleOnAxis());
    final inverse = Matrix4.inverted(transform);
    final visible = Rect.fromPoints(
      MatrixUtils.transformPoint(inverse, Offset.zero),
      MatrixUtils.transformPoint(
        inverse,
        Offset(viewport.width, viewport.height),
      ),
    ).inflate(120 / scale);
    final edgePaint = Paint()
      ..color = edge.withValues(alpha: scale < .18 ? .42 : .68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.15 / scale).clamp(1.5, 5.0);
    for (final visual in layout.edgeVisuals) {
      if (!visual.bounds.overlaps(visible)) continue;
      canvas.drawPath(visual.path, edgePaint);
      if (scale >= .2) canvas.drawPath(visual.arrow, edgePaint);
    }

    final fillPaint = Paint()..color = surface;
    final outlinePaint = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1 / scale).clamp(1.0, 4.0);
    for (final node in layout.nodes) {
      final rect = node.position & _FlatMapLayout.nodeSize;
      if (!rect.overlaps(visible)) continue;
      final card = RRect.fromRectAndRadius(rect, const Radius.circular(12));
      canvas.drawRRect(card, fillPaint);
      if (scale >= .1) canvas.drawRRect(card, outlinePaint);
      if (scale < .16) continue;
      final title = _titles.putIfAbsent(
        node.id,
        () => _textPainter(
          node.title,
          color: text,
          size: 15,
          weight: FontWeight.w600,
          maxLines: 1,
        ),
      );
      title.paint(canvas, rect.topLeft + const Offset(16, 15));
      final description = node.description.trim();
      if (scale < .38 || description.isEmpty) continue;
      final body = _descriptions.putIfAbsent(
        node.id,
        () => _textPainter(description, color: muted, size: 12, maxLines: 3),
      );
      body.paint(canvas, rect.topLeft + const Offset(16, 46));
    }
  }

  TextPainter _textPainter(
    String value, {
    required Color color,
    required double size,
    FontWeight weight = FontWeight.w400,
    required int maxLines,
  }) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(color: color, fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
    maxLines: maxLines,
    ellipsis: '…',
  )..layout(maxWidth: _FlatMapLayout.nodeSize.width - 32);

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final node in layout.nodes)
          CustomPainterSemantics(
            key: ValueKey('overview-node-${node.id}'),
            rect: node.position & _FlatMapLayout.nodeSize,
            properties: SemanticsProperties(
              label: node.title,
              textDirection: TextDirection.ltr,
              readOnly: true,
            ),
          ),
      ];

  @override
  bool shouldRepaint(covariant _FlatMapPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.viewport != viewport ||
      oldDelegate.surface != surface ||
      oldDelegate.line != line ||
      oldDelegate.text != text ||
      oldDelegate.muted != muted ||
      oldDelegate.edge != edge;

  @override
  bool shouldRebuildSemantics(covariant _FlatMapPainter oldDelegate) =>
      oldDelegate.layout != layout;
}

List<ArchitectureEdge> _flattenEdges(
  List<ArchitectureNode> nodes,
  List<ArchitectureGroup> groups,
  List<ArchitectureEdge> edges,
) {
  final nodeIds = nodes.map((node) => node.id).toSet();
  final groupIds = groups.map((group) => group.id).toSet();
  final outgoing = <String, List<String>>{};
  for (final edge in edges) {
    outgoing.putIfAbsent(edge.from, () => []).add(edge.to);
  }
  final pairs = <(String, String)>{};
  for (final source in nodeIds) {
    final queue = <String>[...(outgoing[source] ?? const [])];
    final seenGroups = <String>{};
    for (var index = 0; index < queue.length; index++) {
      final target = queue[index];
      if (nodeIds.contains(target)) {
        if (target != source) pairs.add((source, target));
      } else if (groupIds.contains(target) && seenGroups.add(target)) {
        queue.addAll(outgoing[target] ?? const []);
      }
    }
  }
  final ordered = pairs.toList()
    ..sort((a, b) {
      final from = a.$1.compareTo(b.$1);
      return from == 0 ? a.$2.compareTo(b.$2) : from;
    });
  return [
    for (var index = 0; index < ordered.length; index++)
      ArchitectureEdge(
        id: 'overview-$index',
        from: ordered[index].$1,
        to: ordered[index].$2,
      ),
  ];
}
