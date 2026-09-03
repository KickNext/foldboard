import 'dart:ui';

import '../models/architecture_models.dart';
import 'layout_graph.dart';

class ArchitectureLayout {
  const ArchitectureLayout({
    required this.nodePositions,
    required this.groupFrames,
  });

  final Map<String, Offset> nodePositions;
  final Map<String, Rect> groupFrames;
}

/// Layout a validated hierarchy bottom-up. At each level a child area is one
/// measured box, so it cannot overlap its siblings or unrelated blocks.
class AutoLayoutArchitecture {
  const AutoLayoutArchitecture();

  static const _nodeSize = Size(260, 118);
  static const _columnGap = 180.0;
  static const _rowGap = 64.0;
  static const _padding = Offset(40, 64);

  ArchitectureLayout call({
    required List<ArchitectureNode> nodes,
    required List<ArchitectureEdge> edges,
    required List<ArchitectureGroup> groups,
  }) {
    final areaNodes = <String?, List<ArchitectureNode>>{};
    final areaGroups = <String?, List<ArchitectureGroup>>{};
    for (final node in nodes) {
      (areaNodes[node.parentId] ??= []).add(node);
    }
    for (final group in groups) {
      (areaGroups[group.parentId] ??= []).add(group);
    }

    _Box measure(String? areaId) {
      final children = <_Box>[
        for (final node in areaNodes[areaId] ?? <ArchitectureNode>[])
          _Box(node.id, _nodeSize, {node.id: Offset.zero}, {}),
        for (final group in areaGroups[areaId] ?? <ArchitectureGroup>[])
          measure(group.id),
      ];
      if (children.isEmpty) {
        const size = Size(340, 180);
        return _Box(areaId, size, {}, {?areaId: Offset.zero & size});
      }

      final owners = <String, _Box>{
        for (final box in children)
          for (final id in box.nodes.keys) id: box,
      };
      final links = <_Link>[];
      for (final edge in edges) {
        final from = owners[edge.from];
        final to = owners[edge.to];
        if (from == null || to == null || identical(from, to)) continue;
        links.add(
          _Link(
            from.id!,
            to.id!,
            from.nodes[edge.from]!.dy + _nodeSize.height / 2,
            to.nodes[edge.to]!.dy + _nodeSize.height / 2,
          ),
        );
      }
      final positions = _place(children, links);
      final padding = areaId == null ? Offset.zero : _padding;
      final placedNodes = <String, Offset>{};
      final frames = <String, Rect>{};
      var right = 0.0;
      var bottom = 0.0;
      for (final box in children) {
        final offset = positions[box.id]! + padding;
        placedNodes.addAll(box.nodes.map((id, p) => MapEntry(id, p + offset)));
        frames.addAll(box.frames.map((id, r) => MapEntry(id, r.shift(offset))));
        if (offset.dx + box.size.width > right) {
          right = offset.dx + box.size.width;
        }
        if (offset.dy + box.size.height > bottom) {
          bottom = offset.dy + box.size.height;
        }
      }
      final size = Size(right + padding.dx, bottom + padding.dx);
      if (areaId != null) frames[areaId] = Offset.zero & size;
      return _Box(areaId, size, placedNodes, frames);
    }

    final root = measure(null);
    const origin = Offset(420, 260);
    return ArchitectureLayout(
      nodePositions: root.nodes.map((id, p) => MapEntry(id, p + origin)),
      groupFrames: root.frames.map((id, r) => MapEntry(id, r.shift(origin))),
    );
  }

  Map<String, Offset> _place(List<_Box> boxes, List<_Link> links) {
    boxes = [...boxes]..sort((a, b) => a.id!.compareTo(b.id!));
    links = [...links]
      ..sort((a, b) {
        final from = a.from.compareTo(b.from);
        return from == 0 ? a.to.compareTo(b.to) : from;
      });
    final byId = {for (final b in boxes) b.id!: b};
    final inputLinks = {for (final id in byId.keys) id: <_Link>[]};
    final outputLinks = {for (final id in byId.keys) id: <_Link>[]};
    for (final link in links) {
      inputLinks[link.to]!.add(link);
      outputLinks[link.from]!.add(link);
    }

    final dag = LayoutGraph(
      byId.keys,
      links.map((link) => (link.from, link.to)),
    ).rankingDag();
    final rank = {for (final id in byId.keys) id: 0};
    final degree = {for (final id in byId.keys) id: 0};
    for (final targets in dag.values) {
      for (final target in targets) {
        degree[target] = degree[target]! + 1;
      }
    }
    final queue = byId.keys.where((id) => degree[id] == 0).toList();
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
      for (final target in dag[id]!) {
        if (rank[target]! <= rank[id]!) rank[target] = rank[id]! + 1;
        degree[target] = degree[target]! - 1;
        if (degree[target] == 0) queue.add(target);
      }
    }
    final layers = <int, List<String>>{};
    for (final id in byId.keys) {
      (layers[rank[id]!] ??= []).add(id);
    }
    final layerIds = layers.keys.toList()..sort();
    final x = <String, double>{};
    final y = <String, double>{};
    var left = 0.0;
    for (final layerId in layerIds) {
      var top = 0.0;
      var width = 0.0;
      for (final id in layers[layerId]!) {
        x[id] = left;
        y[id] = top;
        top += byId[id]!.size.height + _rowGap;
        if (byId[id]!.size.width > width) width = byId[id]!.size.width;
      }
      left += width + _columnGap;
    }

    // Align the actual endpoints inside compound boxes, not area centres.
    // Each sweep also sorts by neighbours to untangle simple parallel arrows.
    void sweep(bool forward) {
      for (final layerId in forward ? layerIds : layerIds.reversed) {
        final layer = layers[layerId]!;
        final desired = <String, double>{};
        final previousOrder = {
          for (var i = 0; i < layer.length; i++) layer[i]: i,
        };
        for (final id in layer) {
          final neighbours = forward ? inputLinks[id]! : outputLinks[id]!;
          final samples = <double>[
            for (final link in neighbours)
              if (rank[link.from]! < rank[link.to]!)
                forward
                    ? y[link.from]! + link.sourceY - link.targetY
                    : y[link.to]! + link.targetY - link.sourceY,
          ];
          desired[id] = samples.isEmpty
              ? y[id]!
              : samples.reduce((a, b) => a + b) / samples.length;
        }
        layer.sort((a, b) {
          final difference = desired[a]!.compareTo(desired[b]!);
          return difference != 0
              ? difference
              : previousOrder[a]!.compareTo(previousOrder[b]!);
        });
        var bottom = double.negativeInfinity;
        var correction = 0.0;
        for (final id in layer) {
          final target = desired[id]!;
          final top = target < bottom ? bottom : target;
          y[id] = top;
          correction += target - top;
          bottom = top + byId[id]!.size.height + _rowGap;
        }
        // Keep a fan-out centred around its source after removing collisions.
        correction /= layer.length;
        for (final id in layer) {
          y[id] = y[id]! + correction;
        }
      }
    }

    for (var pass = 0; pass < 4; pass++) {
      sweep(true);
      sweep(false);
    }
    final minY = y.values.reduce((a, b) => a < b ? a : b);
    return {for (final id in byId.keys) id: Offset(x[id]!, y[id]! - minY)};
  }
}

class _Box {
  const _Box(this.id, this.size, this.nodes, this.frames);
  final String? id;
  final Size size;
  final Map<String, Offset> nodes;
  final Map<String, Rect> frames;
}

class _Link {
  const _Link(this.from, this.to, this.sourceY, this.targetY);
  final String from;
  final String to;
  final double sourceY;
  final double targetY;
}
