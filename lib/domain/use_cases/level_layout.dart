import 'dart:math' as math;
import 'dart:ui';

import '../models/architecture_models.dart';
import 'auto_layout_architecture.dart';
import 'layout_graph.dart';

class LayoutRouteMetrics {
  const LayoutRouteMetrics(
    this.bounds, {
    this.collisions = 0,
    this.crossings = 0,
    this.length = 0,
    this.bends = 0,
  });
  final Rect bounds;
  final int collisions;
  final int crossings;
  final double length;
  final int bends;
}

typedef MeasureLayoutRoutes = LayoutRouteMetrics Function(
  List<ArchitectureNode> nodes,
  List<ArchitectureEdge> edges,
);

enum LevelLayoutMode { tidy, rebuild }

/// Flat, process-card layout. Geometry is canonical; translation preserves the
/// user's anchor. The viewport is an explicit input, never inferred from positions.
class LevelLayout {
  const LevelLayout({this.ranker = const AutoLayoutArchitecture()});
  final AutoLayoutArchitecture ranker;
  static const cardSize = Size(260, 118);

  Map<String, Offset> call({
    required List<ArchitectureNode> nodes,
    required List<ArchitectureEdge> edges,
    required List<ArchitectureEdge> rankingEdges,
    required Size viewport,
    String? anchorId,
    MeasureLayoutRoutes? measureRoutes,
    LevelLayoutMode mode = LevelLayoutMode.tidy,
  }) {
    if (nodes.isEmpty) return {};
    final byId = {for (final n in nodes) n.id: n};
    final graph = LayoutGraph(byId.keys, edges.map((e) => (e.from, e.to)));
    final adjustmentMode =
        mode == LevelLayoutMode.tidy &&
        _sketchDirection(nodes, rankingEdges) != null;
    final width = math.max(320.0, viewport.width);
    final height = math.max(240.0, viewport.height);
    final creationVertical = height > width * 1.05;
    final pieces = <_Piece>[];
    for (final ids in graph.components()) {
      final members = ids.toSet();
      final componentNodes = [
        for (final id in ids) byId[id]!.copyWith(clearParent: true),
      ];
      final componentEdges = edges
          .where((e) => members.contains(e.from) && members.contains(e.to))
          .toList();
      final componentRankingEdges = rankingEdges
          .where((e) => members.contains(e.from) && members.contains(e.to))
          .toList();
      final preferredVertical = mode == LevelLayoutMode.tidy
          ? _sketchDirection(componentNodes, componentRankingEdges)
          : null;
      final ranked = ranker(
        nodes: componentNodes,
        edges: componentRankingEdges,
        groups: const [],
      ).nodePositions;
      final bounds = _bounds(ranked);
      _Piece? best;
      if (preferredVertical != null) {
        // Adjustment mode: keep the user's axis and order. Reuse graph ranks,
        // but solve only the spacing and alignment that make the sketch tidy.
        final positions = _tidyToFixedPoint(
          componentNodes,
          componentRankingEdges,
          vertical: preferredVertical,
        );
        final metrics =
            measureRoutes?.call([
              for (final n in componentNodes)
                n.copyWith(position: positions[n.id]),
            ], componentEdges) ??
            LayoutRouteMetrics(_bounds(positions));
        final envelope = metrics.bounds.expandToInclude(_bounds(positions));
        best = _Piece(
          positions,
          envelope.size,
          metrics,
          preferredVertical,
          _movement(positions, componentNodes, null),
        );
      } else {
        // Creation mode: no trustworthy sketch exists. Try a small fixed set
        // of complete layered layouts and choose the cleanest one.
        for (final vertical in [false, true]) {
          for (final mirrored in [false, true]) {
            final positions = <String, Offset>{};
            for (final id in ids) {
              final p = ranked[id]! - bounds.topLeft;
              final cross = mirrored
                  ? bounds.height - cardSize.height - p.dy
                  : p.dy;
              positions[id] = vertical
                  ? Offset(cross * 340 / 182, p.dx * 218 / 440)
                  : Offset(p.dx, cross);
            }
            final arranged = [
              for (final n in componentNodes)
                n.copyWith(position: positions[n.id]),
            ];
            final metrics =
                measureRoutes?.call(arranged, componentEdges) ??
                LayoutRouteMetrics(_bounds(positions));
            final envelope = metrics.bounds.expandToInclude(_bounds(positions));
            final normalized = positions.map(
              (id, p) => MapEntry(id, p - envelope.topLeft),
            );
            final piece = _Piece(
              normalized,
              envelope.size,
              metrics,
              vertical,
              _movement(normalized, componentNodes, anchorId),
            );
            if (best == null ||
                _compare(piece, best, width, height, creationVertical) < 0) {
              best = piece;
            }
          }
        }
      }
      // Bounded refinement of same-rank order using actual route crossings.
      if (preferredVertical == null &&
          measureRoutes != null &&
          ids.length <= 30 &&
          best!.metrics.crossings > 0) {
        var attempts = 0;
        for (var i = 0; i < ids.length && attempts < 6; i++) {
          for (var j = i + 1; j < ids.length && attempts < 6; j++) {
            final current = best!;
            final a = current.positions[ids[i]]!;
            final b = current.positions[ids[j]]!;
            if ((current.vertical ? a.dy - b.dy : a.dx - b.dx).abs() > .001) {
              continue;
            }
            attempts++;
            final swapped = {...current.positions, ids[i]: b, ids[j]: a};
            final metrics = measureRoutes([
              for (final n in componentNodes)
                n.copyWith(position: swapped[n.id]),
            ], componentEdges);
            final envelope = metrics.bounds.expandToInclude(_bounds(swapped));
            final candidate = _Piece(
              swapped.map((id, p) => MapEntry(id, p - envelope.topLeft)),
              envelope.size,
              metrics,
              current.vertical,
              _movement(swapped, componentNodes, anchorId),
            );
            if (_compare(candidate, current, width, height, creationVertical) <
                0) {
              best = candidate;
            }
          }
        }
      }
      if (preferredVertical == null) {
        final createdNodes = [
          for (final node in componentNodes)
            node.copyWith(position: best!.positions[node.id]),
        ];
        final direction = _sketchDirection(createdNodes, componentRankingEdges);
        if (direction != null) {
          final positions = _tidyToFixedPoint(
            createdNodes,
            componentRankingEdges,
            vertical: direction,
          );
          final metrics =
              measureRoutes?.call([
                for (final node in createdNodes)
                  node.copyWith(position: positions[node.id]),
              ], componentEdges) ??
              LayoutRouteMetrics(_bounds(positions));
          final envelope = metrics.bounds.expandToInclude(_bounds(positions));
          best = _Piece(
            positions.map((id, p) => MapEntry(id, p - envelope.topLeft)),
            envelope.size,
            metrics,
            direction,
            _movement(positions, componentNodes, anchorId),
          );
        }
      }
      pieces.add(best!);
    }

    Map<String, Offset>? packed;
    if (adjustmentMode) {
      // Independent areas already have a place in the user's mental map.
      // Keep each component around its old centre instead of shelf-packing it.
      packed = <String, Offset>{};
      for (final piece in pieces) {
        packed.addAll(piece.positions);
      }
      packed = _resolveOverlaps(packed, preferredVertical: null);
    } else {
      // No readable sketch exists. Shelf-pack complete components INCLUDING
      // arrow extents, trying a small deterministic set of row widths.
      var bestCost = double.infinity;
      final area = pieces.fold(
        0.0,
        (sum, p) => sum + (p.size.width + 100) * (p.size.height + 100),
      );
      final widest = pieces.map((p) => p.size.width).reduce(math.max);
      final ideal = math.max(widest, math.sqrt(area * width / height));
      for (final factor in [.7, 1.0, 1.4, 2.0]) {
        final rowWidth = math.max(widest, ideal * factor);
        final candidate = <String, Offset>{};
        var x = 0.0;
        var y = 0.0;
        var rowHeight = 0.0;
        var right = 0.0;
        for (final piece in pieces) {
          if (x > 0 && x + piece.size.width > rowWidth) {
            x = 0;
            y += rowHeight + 100;
            rowHeight = 0;
          }
          candidate.addAll(
            piece.positions.map((id, p) => MapEntry(id, p + Offset(x, y))),
          );
          right = math.max(right, x + piece.size.width);
          rowHeight = math.max(rowHeight, piece.size.height);
          x += piece.size.width + 100;
        }
        final cost = math.max(right / width, (y + rowHeight) / height);
        if (cost < bestCost) {
          bestCost = cost;
          packed = candidate;
        }
      }
    }
    // Quantize canonical geometry first. The selected card's world position is
    // exact; otherwise keep the old bounding-box center (not a fixed origin).
    final rounded = adjustmentMode
        ? packed!
        : packed!.map(
            (id, p) => MapEntry(
              id,
              Offset(
                (p.dx * 1000).round() / 1000,
                (p.dy * 1000).round() / 1000,
              ),
            ),
          );
    final old = {for (final n in nodes) n.id: n.position};
    final delta = adjustmentMode
        ? Offset.zero
        : rounded.containsKey(anchorId)
        ? old[anchorId]! - rounded[anchorId]!
        : _bounds(old).center - _bounds(rounded).center;
    final result = rounded.map((id, p) {
      final moved = p + delta;
      return MapEntry(
        id,
        (moved - old[id]!).distance < .001 ? old[id]! : moved,
      );
    });
    if (result.entries.every((e) => (e.value - old[e.key]!).distance < .001)) {
      return old;
    }
    return result;
  }

  static Rect _bounds(Map<String, Offset> positions) => positions.values
      .map((p) => p & cardSize)
      .reduce((a, b) => a.expandToInclude(b));

  bool? _preferredVertical(
    List<ArchitectureNode> nodes,
    List<ArchitectureEdge> edges,
  ) {
    final byId = {for (final node in nodes) node.id: node.position};
    var horizontal = 0.0;
    var vertical = 0.0;
    for (final edge in edges) {
      final from = byId[edge.from];
      final to = byId[edge.to];
      if (from == null || to == null) continue;
      final delta = to - from;
      // Overlapping or barely separated cards do not express an intention.
      if (delta.distance < cardSize.height * .5) continue;
      horizontal += delta.dx.abs();
      vertical += delta.dy.abs();
    }
    final strongest = math.max(horizontal, vertical);
    if (strongest < cardSize.height) return null;
    // A diagonal sketch is ambiguous. Let route quality and viewport decide.
    if ((horizontal - vertical).abs() < strongest * .2) return null;
    return vertical > horizontal;
  }

  bool? _sketchDirection(
    List<ArchitectureNode> nodes,
    List<ArchitectureEdge> edges,
  ) {
    final direction = _preferredVertical(nodes, edges);
    if (direction == null) return null;
    var overlaps = 0;
    for (var i = 0; i < nodes.length; i++) {
      final first = nodes[i].position & cardSize;
      for (var j = i + 1; j < nodes.length; j++) {
        if (first.overlaps(nodes[j].position & cardSize)) overlaps++;
      }
    }
    // One accidental collision is exactly what Tidy should fix. A pile of
    // default-position cards is not a sketch and needs its first real layout.
    return overlaps <= math.max(1, nodes.length ~/ 4) ? direction : null;
  }

  Map<String, Offset> _tidyExisting(
    List<ArchitectureNode> nodes,
    List<ArchitectureEdge> edges, {
    required bool vertical,
  }) {
    var positions = {for (final node in nodes) node.id: node.position};
    final incoming = {for (final node in nodes) node.id: 0};
    final outgoing = {for (final node in nodes) node.id: 0};
    for (final edge in edges) {
      if (incoming.containsKey(edge.to) && outgoing.containsKey(edge.from)) {
        incoming[edge.to] = incoming[edge.to]! + 1;
        outgoing[edge.from] = outgoing[edge.from]! + 1;
      }
    }

    double flow(Offset p) => vertical ? p.dy : p.dx;
    double cross(Offset p) => vertical ? p.dx : p.dy;
    Offset withFlow(Offset p, double value) =>
        vertical ? Offset(p.dx, value) : Offset(value, p.dy);
    Offset withCross(Offset p, double value) =>
        vertical ? Offset(value, p.dy) : Offset(p.dx, value);

    // Only a nearly straight, non-branching chain is snapped to one rail.
    // Branches retain the lanes the person gave them.
    final parent = {for (final node in nodes) node.id: node.id};
    String root(String id) {
      var current = id;
      while (parent[current] != current) {
        current = parent[current]!;
      }
      var cursor = id;
      while (parent[cursor] != cursor) {
        final next = parent[cursor]!;
        parent[cursor] = current;
        cursor = next;
      }
      return current;
    }

    void unite(String a, String b) {
      final left = root(a);
      final right = root(b);
      if (left != right) parent[right] = left;
    }

    final minimumFlowGap = vertical ? 190.0 : 360.0;
    for (final edge in edges) {
      final from = positions[edge.from];
      final to = positions[edge.to];
      if (from == null || to == null) continue;
      final flowDistance = flow(to) - flow(from);
      final crossDistance = (cross(from) - cross(to)).abs();
      if (outgoing[edge.from] == 1 &&
          incoming[edge.to] == 1 &&
          flowDistance > 0 &&
          flowDistance >= crossDistance * 1.15) {
        unite(edge.from, edge.to);
      }
    }
    final rails = <String, List<String>>{};
    for (final id in positions.keys) {
      (rails[root(id)] ??= []).add(id);
    }
    for (final ids in rails.values) {
      if (ids.length < 2) continue;
      ids.sort((a, b) {
        final order = flow(positions[a]!).compareTo(flow(positions[b]!));
        return order != 0 ? order : a.compareTo(b);
      });
      final rail = _median([for (final id in ids) cross(positions[id]!)]);
      for (final id in ids) {
        positions[id] = withCross(positions[id]!, rail);
      }
      if (ids.length >= 3) {
        final start = flow(positions[ids.first]!);
        final span = flow(positions[ids.last]!) - start;
        final gap = math.max(minimumFlowGap, span / (ids.length - 1));
        for (var i = 1; i < ids.length; i++) {
          positions[ids[i]] = withFlow(positions[ids[i]]!, start + gap * i);
        }
      }
    }

    // Keep every safe gap. Only push a target when an existing forward edge
    // is too short; never assign fresh ranks or normalize all distances.
    final orderedEdges = [...edges]
      ..sort((a, b) {
        final from = a.from.compareTo(b.from);
        return from != 0 ? from : a.to.compareTo(b.to);
      });
    for (var pass = 0; pass < nodes.length; pass++) {
      var changed = false;
      for (final edge in orderedEdges) {
        final from = positions[edge.from];
        final to = positions[edge.to];
        if (from == null || to == null) continue;
        final distance = flow(to) - flow(from);
        if (distance >= 0 && distance < minimumFlowGap) {
          positions[edge.to] = withFlow(to, flow(from) + minimumFlowGap);
          changed = true;
        }
      }
      if (!changed) break;
    }
    return _resolveOverlaps(positions, preferredVertical: vertical);
  }

  Map<String, Offset> _tidyToFixedPoint(
    List<ArchitectureNode> nodes,
    List<ArchitectureEdge> edges, {
    required bool vertical,
  }) {
    var current = nodes;
    var positions = {for (final node in nodes) node.id: node.position};
    for (var pass = 0; pass < math.min(8, nodes.length + 1); pass++) {
      final next = _tidyExisting(current, edges, vertical: vertical);
      if (next.entries.every(
        (entry) => (entry.value - positions[entry.key]!).distance < .001,
      )) {
        return next;
      }
      positions = next;
      current = [
        for (final node in current) node.copyWith(position: positions[node.id]),
      ];
    }
    return positions;
  }

  double _median(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  Map<String, Offset> _resolveOverlaps(
    Map<String, Offset> source, {
    required bool? preferredVertical,
  }) {
    final positions = {...source};
    final ids = positions.keys.toList()..sort();
    const gap = 24.0;
    for (var pass = 0; pass < math.max(1, ids.length * 4); pass++) {
      var changed = false;
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final aId = ids[i];
          final bId = ids[j];
          final a = positions[aId]!;
          final b = positions[bId]!;
          final dx = b.dx - a.dx;
          final dy = b.dy - a.dy;
          final neededX = cardSize.width + gap - dx.abs();
          final neededY = cardSize.height + gap - dy.abs();
          if (neededX <= .001 || neededY <= .001) continue;

          final separateX = switch (preferredVertical) {
            true => dy.abs() < cardSize.height * .45,
            false => dx.abs() >= cardSize.width * .45,
            null => neededX <= neededY,
          };
          if (separateX) {
            final sign = dx == 0 ? 1.0 : dx.sign;
            final shift = neededX / 2;
            positions[aId] = a.translate(-sign * shift, 0);
            positions[bId] = b.translate(sign * shift, 0);
          } else {
            final sign = dy == 0 ? 1.0 : dy.sign;
            final shift = neededY / 2;
            positions[aId] = a.translate(0, -sign * shift);
            positions[bId] = b.translate(0, sign * shift);
          }
          changed = true;
        }
      }
      if (!changed) break;
    }
    return positions;
  }

  double _movement(
    Map<String, Offset> candidate,
    List<ArchitectureNode> nodes,
    String? anchorId,
  ) {
    final old = {for (final node in nodes) node.id: node.position};
    final delta = anchorId != null && candidate.containsKey(anchorId)
        ? old[anchorId]! - candidate[anchorId]!
        : _bounds(old).center - _bounds(candidate).center;
    var distance = 0.0;
    for (final entry in candidate.entries) {
      distance += (entry.value + delta - old[entry.key]!).distance;
    }
    return distance / candidate.length;
  }

  int _compare(
    _Piece a,
    _Piece b,
    double width,
    double height,
    bool? preferredVertical,
  ) {
    // A readable sketch keeps its direction. A new layout follows the shape of
    // the available board, so a cycle cannot make the whole flow turn sideways.
    if (preferredVertical != null) {
      final orientation = (a.vertical == preferredVertical ? 0 : 1).compareTo(
        b.vertical == preferredVertical ? 0 : 1,
      );
      if (orientation != 0) return orientation;
    }
    var comparison = a.metrics.collisions.compareTo(b.metrics.collisions);
    if (comparison != 0) return comparison;
    comparison = a.metrics.crossings.compareTo(b.metrics.crossings);
    if (comparison != 0) return comparison;
    if (preferredVertical != null) {
      final movementDifference = a.movement - b.movement;
      if (movementDifference.abs() > 1) return movementDifference.sign.toInt();
    }
    // Readability and wire complexity, normalized to card-sized units.
    double cost(_Piece p) =>
        math.max(p.size.width / width, p.size.height / height) +
        .08 * p.metrics.length / math.max(1, p.positions.length) / 440 +
        .01 * p.metrics.bends / math.max(1, p.positions.length);
    return cost(a).compareTo(cost(b));
  }
}

class _Piece {
  const _Piece(
    this.positions,
    this.size,
    this.metrics,
    this.vertical,
    this.movement,
  );
  final Map<String, Offset> positions;
  final Size size;
  final LayoutRouteMetrics metrics;
  final bool vertical;
  final double movement;
}
