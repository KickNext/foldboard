import 'dart:math' as math;

import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/edge_routes.dart';
import 'package:flutter_test/flutter_test.dart';

ArchitectureNode node(String id, double x, double y) =>
    ArchitectureNode(id: id, title: id, position: Offset(x, y));

ArchitectureEdge edge(String id, String from, String to) =>
    ArchitectureEdge(id: id, from: from, to: to);

void expectClear(List<EdgeRoute> routes, List<ArchitectureNode> nodes) {
  for (final route in routes) {
    for (final metric in route.path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 3) {
        final point = metric.getTangentForOffset(d)!.position;
        for (final n in nodes) {
          expect(
            (n.position & EdgeRouter.cardSize).deflate(.1).contains(point),
            isFalse,
            reason: '${route.edge.id} enters ${n.id} at $point',
          );
        }
        expect(route.distanceTo(point), lessThan(.6));
      }
    }
  }
}

double sharedVerticalLength(EdgeRoute a, EdgeRoute b) {
  var longest = 0.0;
  for (var i = 1; i < a.points.length; i++) {
    final a0 = a.points[i - 1];
    final a1 = a.points[i];
    if ((a0.dx - a1.dx).abs() > .001) continue;
    for (var j = 1; j < b.points.length; j++) {
      final b0 = b.points[j - 1];
      final b1 = b.points[j];
      if ((b0.dx - b1.dx).abs() > .001 || (a0.dx - b0.dx).abs() > .001) {
        continue;
      }
      final overlap =
          math.min(math.max(a0.dy, a1.dy), math.max(b0.dy, b1.dy)) -
          math.max(math.min(a0.dy, a1.dy), math.min(b0.dy, b1.dy));
      longest = math.max(longest, overlap);
    }
  }
  return longest;
}

void main() {
  test('stacked reference cards have separate feedback stems, not just horizontal lanes', () {
    final nodes = [
      node('human', 100, 100),
      node('agent', 100, 282),
      node('graph', 700, 100),
      node('json', 1200, 382),
    ];
    final edges = [
      edge('1', 'json', 'human'),
      edge('2', 'json', 'agent'),
      edge('3', 'graph', 'agent'),
      edge('4', 'graph', 'human'),
    ];
    final routes = EdgeRouter().route(nodes, edges);
    expectClear(routes, nodes);
    for (var i = 0; i < routes.length; i++) {
      for (var j = i + 1; j < routes.length; j++) {
        expect(
          sharedVerticalLength(routes[i], routes[j]),
          lessThan(2),
          reason: '${routes[i].edge.id} stacks on ${routes[j].edge.id}',
        );
      }
    }
    final humanTips = routes
        .where((r) => r.edge.to == 'human')
        .map((r) => r.tip.dy)
        .toList();
    expect((humanTips[0] - humanTips[1]).abs(), greaterThanOrEqualTo(18));
    expect(
      EdgeRouter().route(nodes, edges.reversed.toList()).map((r) => r.points),
      routes.map((r) => r.points),
    );
  });

  test(
    'vertical fan-in keeps distinct target ports and smooth, hittable paths',
    () {
      final nodes = [node('a', 0, 0), node('b', 0, 220), node('c', 0, 600)];
      final routes = EdgeRouter().route(nodes, [
        edge('ac', 'a', 'c'),
        edge('bc', 'b', 'c'),
      ]);
      expect(
        (routes[0].tip.dx - routes[1].tip.dx).abs(),
        greaterThanOrEqualTo(18),
      );
      expect(sharedVerticalLength(routes[0], routes[1]), lessThan(2));
      expectClear(routes, nodes);
      for (final route in routes) {
        expect(route.angle, closeTo(math.pi / 2, .001));
      }
    },
  );

  test('vertical arrows use facing sides, including offset cards', () {
    for (final dx in [-40.0, 0.0, 40.0]) {
      final nodes = [node('a', 0, 0), node('b', dx, 350)];
      for (final down in [true, false]) {
        final route = EdgeRouter().route(nodes, [
          edge('link', down ? 'a' : 'b', down ? 'b' : 'a'),
        ]).single;
        expect(
          route.points.first,
          down ? const Offset(130, 118) : Offset(dx + 130, 350),
        );
        expect(
          route.tip,
          down ? Offset(dx + 130, 350) : const Offset(130, 118),
        );
        expect(route.angle, closeTo(down ? math.pi / 2 : -math.pi / 2, .1));
        expect(route.bounds.top, greaterThanOrEqualTo(118));
        expect(route.bounds.bottom, lessThanOrEqualTo(350));
        expectClear([route], nodes);
      }
    }
  });

  test('opposite vertical arrows keep separate ports', () {
    final nodes = [node('a', 0, 0), node('b', 0, 350)];
    final routes = EdgeRouter().route(nodes, [
      edge('down', 'a', 'b'),
      edge('up', 'b', 'a'),
    ]);
    expect(routes.first.tip.dy, 350);
    expect(routes.last.tip.dy, 118);
    expect((routes.first.tip.dx - routes.last.tip.dx).abs(), greaterThan(30));
    expectClear(routes, nodes);
  });

  test('vertical obstacle detour still enters the target from the top', () {
    final nodes = [node('a', 0, 0), node('b', 40, 600), node('wall', 0, 250)];
    final route = EdgeRouter().route(nodes, [edge('link', 'a', 'b')]).single;
    expect(route.tip, const Offset(170, 600));
    expect(route.angle, closeTo(math.pi / 2, .001));
    expect(route.bounds.bottom, lessThanOrEqualTo(600));
    expectClear([route], nodes);
  });

  test(
    'covering an endpoint does not turn ordinary arrows into global loops',
    () {
      final nodes = [node('a', 0, 0), node('b', 500, 0), node('c', 1000, 0)];
      final edges = [edge('ab', 'a', 'b'), edge('bc', 'b', 'c')];
      final router = EdgeRouter();
      final original = router.route(nodes, edges);
      for (final offset in [-150.0, -20.0, 0.0, 20.0, 150.0]) {
        final routes = router.route([
          ...nodes,
          node('cover', 500 + offset, -20),
        ], edges);
        for (var i = 0; i < routes.length; i++) {
          expect(routes[i].points, original[i].points);
        }
      }
    },
  );

  test('overlapping connected cards hide only their occluded connection', () {
    final edges = [edge('ab', 'a', 'b'), edge('bc', 'b', 'c')];
    final router = EdgeRouter();
    final nodes = [node('a', 500, 0), node('b', 500, 0), node('c', 1000, 0)];
    expect(router.route(nodes, edges).map((r) => r.edge.id), ['bc']);
    final separated = [node('a', 200, 0), ...nodes.skip(1)];
    expect(router.route(separated, edges).map((r) => r.edge.id), ['ab', 'bc']);
    expect(edges, hasLength(2));
  });

  test('a narrow forward gap does not trigger a feedback loop', () {
    for (final gap in [1.0, 10.0, 39.0, 40.0]) {
      final routes = EdgeRouter().route(
        [node('a', 0, 0), node('b', 260 + gap, 0)],
        [edge('ab', 'a', 'b')],
      );
      expect(routes.single.bounds.top, 59);
      expect(routes.single.bounds.bottom, 59);
    }
  });

  test('a clear right-to-left arrow uses the facing side ports', () {
    final route = EdgeRouter()
        .route(
          [node('left', 0, 0), node('right', 500, 0)],
          [edge('back', 'right', 'left')],
        )
        .single;
    expect(route.points.first, const Offset(500, 59));
    expect(route.tip, const Offset(260, 59));
    expect(route.angle.abs(), closeTo(math.pi, .001));
    expect(route.bounds.top, 59);
    expect(route.bounds.bottom, 59);
  });

  test('opposite arrows use separate paths and correct arrowhead tangents', () {
    final nodes = [node('a', 0, 0), node('b', 500, 0)];
    final routes = EdgeRouter().route(nodes, [
      edge('forward', 'a', 'b'),
      edge('return', 'b', 'a'),
    ]);
    final forward = routes.first;
    final back = routes.last;
    expect(forward.points.first.dx, 260);
    expect(forward.tip.dx, 500);
    expect(forward.angle, closeTo(0, .001));
    expect(back.points.first.dx, 500);
    expect(back.tip.dx, 260);
    expect(back.angle.abs(), closeTo(math.pi, .001));
    expect(back.bounds.bottom, lessThanOrEqualTo(83));
    expect(sharedVerticalLength(forward, back), lessThan(2));
    expect(
      (forward.points.first.dy - back.points.first.dy).abs(),
      greaterThanOrEqualTo(40),
    );
    expectClear(routes, nodes);
  });

  test(
    'real six-card cycle avoids cards and gives feedback separate lanes',
    () {
      final nodes = [
        node('person', 420, 260),
        node('agent', 420, 442),
        node('editor', 860, 260),
        node('graph', 1300, 260),
        node('export', 1740, 260),
        node('bridge', 2620, 260),
      ];
      final routes = EdgeRouter().route(nodes, [
        edge('1', 'person', 'editor'),
        edge('2', 'agent', 'bridge'),
        edge('3', 'editor', 'graph'),
        edge('4', 'bridge', 'graph'),
        edge('5', 'graph', 'export'),
        edge('6', 'export', 'agent'),
      ]);
      expect(routes, hasLength(6));
      expect(routes[1].bounds.top, lessThan(260));
      // Feedback is local to its endpoints, no longer forced below the whole board.
      expect(
        routes[5].bounds.bottom - routes[3].bounds.bottom,
        greaterThanOrEqualTo(24),
      );
      expectClear(routes, nodes);
    },
  );

  test('a clear return arrow ignores unrelated cards below it', () {
    final nodes = [
      node('a', 0, 0),
      node('b', 600, 0),
      node('obstacle-a', 0, 200),
      node('obstacle-b', 600, 200),
    ];
    final routes = EdgeRouter().route(nodes, [edge('return', 'b', 'a')]);
    expect(routes.single.bounds.top, 59);
    expect(routes.single.bounds.bottom, 59);
    expectClear(routes, nodes);
  });

  test('vertical links avoid crossing the target card', () {
    final nodes = [node('a', 0, 0), node('b', 0, 220)];
    final routes = EdgeRouter().route(nodes, [
      edge('1', 'a', 'b'),
      edge('2', 'b', 'a'),
    ]);
    expectClear(routes, nodes);
  });

  test('routes are deterministic and cached for unchanged geometry', () {
    final nodes = [node('a', 0, 0), node('b', 600, 0), node('c', 1200, 0)];
    final edges = [edge('2', 'c', 'a'), edge('1', 'b', 'a')];
    final router = EdgeRouter();
    final routes = router.route(nodes, edges);
    expect(identical(routes, router.route(nodes, edges)), isTrue);
    final reordered = EdgeRouter().route(nodes, edges.reversed.toList());
    expect(reordered.map((r) => r.points), routes.map((r) => r.points));
    final moved = router.route([
      nodes.first.copyWith(position: const Offset(-100, 0)),
      ...nodes.skip(1),
    ], edges);
    expect(moved.first.tip, isNot(routes.first.tip));
  });

  test('invalid links and self links are ignored', () {
    expect(
      EdgeRouter().route(
        [node('a', 0, 0)],
        [edge('1', 'a', 'missing'), edge('2', 'a', 'a')],
      ),
      isEmpty,
    );
  });
}
