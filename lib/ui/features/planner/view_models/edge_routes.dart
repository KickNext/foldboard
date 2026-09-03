import 'dart:math' as math;
import 'dart:ui';

import '../../../../domain/models/architecture_models.dart';
import '../../../../domain/use_cases/layout_graph.dart';

class EdgeRoute {
  EdgeRoute(this.edge, this.path, this.points, {this.endAngle});
  final ArchitectureEdge edge;
  final Path path;
  final List<Offset> points;
  final double? endAngle;
  late final Rect bounds = path.getBounds();
  late final PathMetric? metric = path.computeMetrics().firstOrNull;
  Offset get tip => points.last;
  double get angle =>
      endAngle ?? (points.last - points[points.length - 2]).direction;

  double distanceTo(Offset point) {
    var nearest = double.infinity;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final d = points[i] - a;
      final v = point - a;
      final t = d.distanceSquared == 0
          ? 0.0
          : ((v.dx * d.dx + v.dy * d.dy) / d.distanceSquared).clamp(0.0, 1.0);
      nearest = math.min(nearest, (point - a - d * t).distance);
    }
    return nearest;
  }
}

/// Cached world-space geometry, shared by painting, hit testing and Fit.
class EdgeRouter {
  List<ArchitectureNode>? _nodes;
  List<ArchitectureEdge>? _edges;
  List<EdgeRoute> _routes = const [];
  static const cardSize = Size(260, 118);

  List<EdgeRoute> route(
    List<ArchitectureNode> nodes,
    List<ArchitectureEdge> edges,
  ) {
    if (identical(nodes, _nodes) && identical(edges, _edges)) return _routes;
    _nodes = nodes;
    _edges = edges;
    final boxes = {for (final n in nodes) n.id: n.position & cardSize};
    if (boxes.isEmpty) return _routes = const [];
    final componentFor = <String, int>{};
    final componentBounds = <int, Rect>{};
    final components = LayoutGraph(
      boxes.keys,
      edges.map((e) => (e.from, e.to)),
    ).components();
    for (var i = 0; i < components.length; i++) {
      for (final id in components[i]) {
        componentFor[id] = i;
        componentBounds[i] =
            componentBounds[i]?.expandToInclude(boxes[id]!) ?? boxes[id]!;
      }
    }
    final bottomLanes = <int, int>{};
    final topLanes = <int, int>{};
    final result = <EdgeRoute>[];
    final verticalTracks = _VerticalTracks();
    final portSlots = <(String, int), List<double>>{};
    void addRoute(EdgeRoute route) {
      result.add(route);
      verticalTracks.reserve(route.points);
    }

    final ordered = [...edges]..sort((a, b) => a.id.compareTo(b.id));
    final pairs = {for (final edge in edges) (edge.from, edge.to)};
    for (final edge in ordered) {
      final from = boxes[edge.from];
      final to = boxes[edge.to];
      if (from == null || to == null || edge.from == edge.to) continue;
      // No visible corridor exists between overlapping endpoints. Keep the
      // connection in the document, but do not invent a loop around the pile.
      if (from.overlaps(to)) continue;
      // A card covering an endpoint is an occluder, not a routing obstacle:
      // draw beneath it instead of repeatedly switching ports and global lanes.
      final routingBoxes = {
        for (final entry in boxes.entries)
          if (entry.key == edge.from ||
              entry.key == edge.to ||
              (!entry.value.overlaps(from) && !entry.value.overlaps(to)))
            entry.key: entry.value,
      };
      final verticalGap = math.max(to.top - from.bottom, from.top - to.bottom);
      final centers = to.center - from.center;
      final horizontalGap = math.max(
        to.left - from.right,
        from.left - to.right,
      );
      if (verticalGap > 0 &&
          (horizontalGap <= 0 || centers.dy.abs() > centers.dx.abs())) {
        final down = centers.dy > 0;
        final direction = down ? 1.0 : -1.0;
        // Reciprocal vertical connections use parallel, distinct ports.
        final offset = pairs.contains((edge.to, edge.from))
            ? 24 * direction
            : 0.0;
        final start = _facingPort(from, down, offset, edge.from, portSlots);
        final end = _facingPort(to, !down, offset, edge.to, portSlots);
        final reach = Offset(0, direction * verticalGap * .42);
        final c1 = start + reach;
        final c2 = end - reach;
        final points = <Offset>[start];
        _flattenCubic(start, c1, c2, end, points);
        final blocked = routingBoxes.entries.any(
          (entry) =>
              entry.key != edge.from &&
              entry.key != edge.to &&
              _polylineHits(points, entry.value.inflate(12)),
        );
        if (!blocked) {
          addRoute(
            EdgeRoute(
              edge,
              Path()
                ..moveTo(start.dx, start.dy)
                ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy),
              points,
              endAngle: (end - c2).direction,
            ),
          );
        } else {
          // Detour only around real obstacles, retaining the facing ports.
          final stub = Offset(0, direction * math.min(24, verticalGap / 3));
          final obstacles = routingBoxes.values
              .map((r) => r.inflate(16))
              .toList();
          addRoute(
            _rounded(edge, [
              start,
              ..._orthogonal(
                start + stub,
                end - stub,
                obstacles,
                verticalTracks,
              ),
              end,
            ]),
          );
        }
        continue;
      }
      final right = centers.dx > 0;
      final direction = right ? 1.0 : -1.0;
      final reciprocalOffset = pairs.contains((edge.to, edge.from))
          ? 24 * direction
          : 0.0;
      final start = _facingSidePort(
        from,
        right,
        reciprocalOffset,
        edge.from,
        portSlots,
      );
      final end = _facingSidePort(
        to,
        !right,
        reciprocalOffset,
        edge.to,
        portSlots,
      );
      if (horizontalGap > 0) {
        final reach = horizontalGap * .42 * direction;
        final c1 = start + Offset(reach, 0);
        final c2 = end - Offset(reach, 0);
        final points = <Offset>[start];
        _flattenCubic(start, c1, c2, end, points);
        final blocked = routingBoxes.entries.any(
          (entry) =>
              entry.key != edge.from &&
              entry.key != edge.to &&
              _polylineHits(points, entry.value.inflate(12)),
        );
        if (!blocked) {
          addRoute(
            EdgeRoute(
              edge,
              Path()
                ..moveTo(start.dx, start.dy)
                ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy),
              points,
              endAngle: (end - c2).direction,
            ),
          );
          continue;
        }
      }
      // Only blocked horizontal connections use an outer lane. Their endpoints
      // still use the geometrically facing sides, regardless of graph direction.
      final bottom = !right;
      final component = componentFor[edge.from]!;
      final bounds = componentBounds[component]!;
      final lanes = bottom ? bottomLanes : topLanes;
      final laneIndex = lanes[component] ?? 0;
      lanes[component] = laneIndex + 1;
      final localBounds = from.expandToInclude(to);
      var lane = bottom
          ? localBounds.bottom + 64 + laneIndex * 24
          : localBounds.top - 64 - laneIndex * 24;
      final obstacles = routingBoxes.values.map((r) => r.inflate(16)).toList();
      // Give outer routes enough runway to turn into side ports. A 24px
      // approach capped the rounded corner at 12px and made fan-in routes look
      // like little hooks beside the card, especially when zoomed out.
      final sourceExit = start + Offset(40 * direction, 0);
      final targetExit = end - Offset(40 * direction, 0);
      if (obstacles.any(
        (r) =>
            r.contains(Offset(sourceExit.dx, lane)) ||
            r.contains(Offset(targetExit.dx, lane)),
      )) {
        lane = bottom
            ? bounds.bottom + 64 + (laneIndex + 1) * 24
            : bounds.top - 64 - (laneIndex + 1) * 24;
      }
      final a = Offset(sourceExit.dx, lane);
      final b = Offset(targetExit.dx, lane);
      final first = _orthogonal(sourceExit, a, obstacles, verticalTracks);
      final middle = _orthogonal(a, b, obstacles, verticalTracks);
      final last = _orthogonal(b, targetExit, obstacles, verticalTracks);
      final points = [start, ...first, ...middle.skip(1), ...last.skip(1), end];
      addRoute(_rounded(edge, points, maxRadius: 20));
    }
    return _routes = List.unmodifiable(result);
  }
}

Offset _facingSidePort(
  Rect box,
  bool right,
  double offset,
  String id,
  Map<(String, int), List<double>> slots,
) {
  final used = slots.putIfAbsent((id, right ? 1 : 3), () => []);
  final preferred = box.center.dy + offset;
  for (var i = 0; i <= 12; i++) {
    final shift = i == 0 ? 0.0 : ((i + 1) ~/ 2) * 20.0 * (i.isOdd ? -1 : 1);
    final y = preferred + shift;
    if (y < box.top + 24 ||
        y > box.bottom - 24 ||
        used.any((p) => (p - y).abs() < 18)) {
      continue;
    }
    used.add(y);
    return Offset(right ? box.right : box.left, y);
  }
  return Offset(right ? box.right : box.left, preferred);
}

Offset _facingPort(
  Rect box,
  bool bottom,
  double offset,
  String id,
  Map<(String, int), List<double>> slots,
) {
  final used = slots.putIfAbsent((id, bottom ? 2 : 0), () => []);
  final preferred = box.center.dx + offset;
  for (var i = 0; i <= 24; i++) {
    final shift = i == 0 ? 0.0 : ((i + 1) ~/ 2) * 20.0 * (i.isOdd ? -1 : 1);
    final x = preferred + shift;
    if (x < box.left + 24 ||
        x > box.right - 24 ||
        used.any((p) => (p - x).abs() < 18)) {
      continue;
    }
    used.add(x);
    return Offset(x, bottom ? box.bottom : box.top);
  }
  return Offset(preferred, bottom ? box.bottom : box.top);
}

bool _segmentHits(Offset a, Offset b, Rect r) {
  var low = 0.0;
  var high = 1.0;
  final d = b - a;
  for (final axis in [
    (a.dx, d.dx, r.left, r.right),
    (a.dy, d.dy, r.top, r.bottom),
  ]) {
    if (axis.$2.abs() < .000001) {
      if (axis.$1 <= axis.$3 || axis.$1 >= axis.$4) return false;
    } else {
      final t1 = (axis.$3 - axis.$1) / axis.$2;
      final t2 = (axis.$4 - axis.$1) / axis.$2;
      low = math.max(low, math.min(t1, t2));
      high = math.min(high, math.max(t1, t2));
      if (low >= high) return false;
    }
  }
  return low < high;
}

bool _polylineHits(List<Offset> points, Rect r) {
  for (var i = 1; i < points.length; i++) {
    if (_segmentHits(points[i - 1], points[i], r)) return true;
  }
  return false;
}

void _flattenCubic(
  Offset a,
  Offset b,
  Offset c,
  Offset d,
  List<Offset> out, [
  int depth = 0,
]) {
  final chord = d - a;
  double deviation(Offset p) => chord.distance == 0
      ? (p - a).distance
      : ((p.dx - a.dx) * chord.dy - (p.dy - a.dy) * chord.dx).abs() /
            chord.distance;
  if (depth >= 12 || math.max(deviation(b), deviation(c)) < .5) {
    out.add(d);
    return;
  }
  final ab = (a + b) / 2;
  final bc = (b + c) / 2;
  final cd = (c + d) / 2;
  final abc = (ab + bc) / 2;
  final bcd = (bc + cd) / 2;
  final mid = (abc + bcd) / 2;
  _flattenCubic(a, ab, abc, mid, out, depth + 1);
  _flattenCubic(mid, bcd, cd, d, out, depth + 1);
}

EdgeRoute _rounded(
  ArchitectureEdge edge,
  List<Offset> input, {
  double maxRadius = 12,
}) {
  final corners = <Offset>[];
  for (final p in input) {
    if (corners.isNotEmpty && (corners.last - p).distance < .001) continue;
    while (corners.length > 1) {
      final a = corners[corners.length - 2];
      final b = corners.last;
      final u = b - a;
      final v = p - b;
      if ((u.dx * v.dy - u.dy * v.dx).abs() > .001 ||
          u.dx * v.dx + u.dy * v.dy <= 0) {
        break;
      }
      corners.removeLast();
    }
    corners.add(p);
  }
  final path = Path()..moveTo(corners.first.dx, corners.first.dy);
  final hits = <Offset>[corners.first];
  for (var i = 1; i < corners.length - 1; i++) {
    final p = corners[i];
    final before = corners[i - 1] - p;
    final after = corners[i + 1] - p;
    final radius = math.min(
      maxRadius,
      math.min(before.distance, after.distance) / 2,
    );
    final enter = p + before / before.distance * radius;
    final exit = p + after / after.distance * radius;
    path
      ..lineTo(enter.dx, enter.dy)
      ..quadraticBezierTo(p.dx, p.dy, exit.dx, exit.dy);
    hits.add(enter);
    for (var j = 1; j <= 8; j++) {
      final t = j / 8;
      hits.add(
        enter * ((1 - t) * (1 - t)) + p * (2 * (1 - t) * t) + exit * (t * t),
      );
    }
  }
  path.lineTo(corners.last.dx, corners.last.dy);
  hits.add(corners.last);
  return EdgeRoute(edge, path, hits);
}

// Most legs are clear. Search a sparse, lazily visited coordinate grid only
// when a card blocks an escape leg. Obstacle borders leave room for rounding.
List<Offset> _orthogonal(
  Offset start,
  Offset end,
  List<Rect> obstacles,
  _VerticalTracks tracks,
) {
  bool clear(Offset a, Offset b) =>
      !obstacles.any((r) => _segmentHits(a, b, r));
  if ((start.dx == end.dx || start.dy == end.dy) &&
      clear(start, end) &&
      tracks.overlap(start, end) == 0) {
    return [start, end];
  }
  for (final corner in [Offset(start.dx, end.dy), Offset(end.dx, start.dy)]) {
    if (clear(start, corner) &&
        clear(corner, end) &&
        tracks.overlap(start, corner) == 0 &&
        tracks.overlap(corner, end) == 0) {
      return [start, corner, end];
    }
  }
  // Inflated clearances can close a very narrow gap. Searching the entire grid
  // cannot free a trapped endpoint; let the card occlude this short escape leg.
  bool trapped(Offset p) => obstacles.any(
    (r) => p.dx > r.left && p.dx < r.right && p.dy > r.top && p.dy < r.bottom,
  );
  if (trapped(start) || trapped(end)) return [start, end];
  final xs = {
    start.dx,
    end.dx,
    for (final r in obstacles) ...[r.left, r.right],
    ...tracks.alternatives(start, end),
  }.toList()..sort();
  final ys = {
    start.dy,
    end.dy,
    for (final r in obstacles) ...[r.top, r.bottom],
  }.toList()..sort();
  final width = xs.length;
  int index(Offset p) => ys.indexOf(p.dy) * width + xs.indexOf(p.dx);
  Offset point(int id) => Offset(xs[id % width], ys[id ~/ width]);
  double heuristic(Offset p) => (p.dx - end.dx).abs() + (p.dy - end.dy).abs();
  final first = index(start);
  final goal = index(end);
  final cost = <int, double>{first: 0};
  final parent = <int, int>{};
  final queue = _MinHeap()..add((first, heuristic(start)));
  final settled = <int>{};
  while (queue.isNotEmpty) {
    final id = queue.remove().$1;
    if (!settled.add(id)) continue;
    if (id == goal) {
      final result = <Offset>[end];
      var cursor = id;
      while (cursor != first) {
        cursor = parent[cursor]!;
        result.add(point(cursor));
      }
      return result.reversed.toList();
    }
    final x = id % width;
    final y = id ~/ width;
    final current = point(id);
    for (final next in [
      if (x > 0) id - 1,
      if (x + 1 < width) id + 1,
      if (y > 0) id - width,
      if (y + 1 < ys.length) id + width,
    ]) {
      if (settled.contains(next)) continue;
      final p = point(next);
      if (!clear(current, p)) continue;
      final nextCost =
          cost[id]! + (p - current).distance + tracks.overlap(current, p) * 100;
      if (nextCost >= (cost[next] ?? double.infinity)) continue;
      cost[next] = nextCost;
      parent[next] = id;
      queue.add((next, nextCost + heuristic(p)));
    }
  }
  return [start, end]; // Only possible when cards overlap an endpoint.
}

/// Reserve longitudinal runs, not crossings. Vertical feedback legs use the
/// same spacing discipline as horizontal lanes, without treating wires as walls.
class _VerticalTracks {
  final _runs = <int, List<(double, double, double)>>{};
  int _key(double x) => (x * 1000).round();

  void reserve(List<Offset> points) {
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      if ((a.dx - b.dx).abs() > .0001 || (a.dy - b.dy).abs() < 1) continue;
      (_runs[_key(a.dx)] ??= []).add((
        a.dx,
        math.min(a.dy, b.dy),
        math.max(a.dy, b.dy),
      ));
    }
  }

  double overlap(Offset a, Offset b) {
    if ((a.dx - b.dx).abs() > .0001) return 0;
    final low = math.min(a.dy, b.dy);
    final high = math.max(a.dy, b.dy);
    var total = 0.0;
    for (final run in _runs[_key(a.dx)] ?? const <(double, double, double)>[]) {
      total += math.max(0, math.min(high, run.$3) - math.max(low, run.$2));
    }
    return total;
  }

  Iterable<double> alternatives(Offset start, Offset end) sync* {
    final low = math.min(start.dy, end.dy);
    final high = math.max(start.dy, end.dy);
    for (final runs in _runs.values) {
      if (runs.any((r) => r.$2 < high && r.$3 > low)) {
        yield runs.first.$1 - 20;
        yield runs.first.$1 + 20;
      }
    }
  }
}

class _MinHeap {
  final _items = <(int, double)>[];
  bool get isNotEmpty => _items.isNotEmpty;
  void add((int, double) value) {
    _items.add(value);
    var i = _items.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_items[p].$2 <= value.$2) break;
      _items[i] = _items[p];
      i = p;
    }
    _items[i] = value;
  }

  (int, double) remove() {
    final result = _items.first;
    final last = _items.removeLast();
    if (_items.isEmpty) return result;
    var i = 0;
    while (i * 2 + 1 < _items.length) {
      var child = i * 2 + 1;
      if (child + 1 < _items.length &&
          _items[child + 1].$2 < _items[child].$2) {
        child++;
      }
      if (_items[child].$2 >= last.$2) break;
      _items[i] = _items[child];
      i = child;
    }
    _items[i] = last;
    return result;
  }
}
