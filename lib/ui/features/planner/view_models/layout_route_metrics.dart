import 'dart:math' as math;
import 'dart:ui';

import '../../../../domain/models/architecture_models.dart';
import '../../../../domain/use_cases/level_layout.dart';
import 'edge_routes.dart';

/// Evaluate the same routes that will be painted. Bound expensive comparisons
/// on large graphs; routing remains exact for the chosen visible diagram.
LayoutRouteMetrics measureLayoutRoutes(
  List<ArchitectureNode> nodes,
  List<ArchitectureEdge> edges,
) {
  final boxes = {for (final n in nodes) n.id: n.position & EdgeRouter.cardSize};
  var bounds = boxes.values.reduce((a, b) => a.expandToInclude(b));
  if (nodes.length > 60 || edges.length > 100) {
    final length = edges.fold(
      0.0,
      (sum, e) => sum + (boxes[e.from]!.center - boxes[e.to]!.center).distance,
    );
    // Conservative component gutter for feedback routes in the bounded path.
    return LayoutRouteMetrics(
      bounds.inflate(96 + edges.length * 16),
      length: length,
    );
  }
  final routes = EdgeRouter().route(nodes, edges);
  var length = 0.0;
  var bends = 0;
  var collisions = edges.length - routes.length;
  var crossings = 0;
  final samples = <List<Offset>>[];
  for (final route in routes) {
    bounds = bounds.expandToInclude(route.bounds.inflate(12));
    length += route.metric?.length ?? 0;
    bends += math.max(0, route.points.length - 2);
    // Curves are sampled by arc length, not their control-point polygon.
    final metric = route.metric;
    final points = metric == null
        ? route.points
        : [
            for (var i = 0; i <= 20; i++)
              metric.getTangentForOffset(metric.length * i / 20)!.position,
          ];
    samples.add(points);
    for (final entry in boxes.entries) {
      if (entry.key == route.edge.from || entry.key == route.edge.to) continue;
      if (points.any(entry.value.deflate(1).contains)) collisions++;
    }
  }
  for (var i = 0; i < routes.length; i++) {
    for (var j = i + 1; j < routes.length; j++) {
      final a = routes[i];
      final b = routes[j];
      if (!a.bounds.overlaps(b.bounds) ||
          a.edge.from == b.edge.from ||
          a.edge.to == b.edge.to ||
          a.edge.from == b.edge.to ||
          a.edge.to == b.edge.from) {
        continue;
      }
      var crossed = false;
      for (var x = 1; x < samples[i].length && !crossed; x++) {
        for (var y = 1; y < samples[j].length; y++) {
          if (_crosses(
            samples[i][x - 1],
            samples[i][x],
            samples[j][y - 1],
            samples[j][y],
          )) {
            crossed = true;
            break;
          }
        }
      }
      if (crossed) crossings++;
    }
  }
  return LayoutRouteMetrics(
    bounds,
    collisions: collisions,
    crossings: crossings,
    length: length,
    bends: bends,
  );
}

bool _crosses(Offset a, Offset b, Offset c, Offset d) {
  double side(Offset p, Offset q, Offset r) =>
      (q.dx - p.dx) * (r.dy - p.dy) - (q.dy - p.dy) * (r.dx - p.dx);
  return side(a, b, c) * side(a, b, d) < -.001 &&
      side(c, d, a) * side(c, d, b) < -.001;
}
