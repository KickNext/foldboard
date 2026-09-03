import 'dart:ui';

import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/domain/use_cases/layout_graph.dart';
import 'package:foldboard/domain/use_cases/level_layout.dart';
import 'package:foldboard/ui/features/planner/view_models/layout_route_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

ArchitectureNode node(String id, [Offset p = Offset.zero]) =>
    ArchitectureNode(id: id, title: id, position: p);
ArchitectureEdge edge(String a, String b) =>
    ArchitectureEdge(id: '$a-$b', from: a, to: b);
Rect bounds(Map<String, Offset> p) => p.values
    .map((p) => p & LevelLayout.cardSize)
    .reduce((a, b) => a.expandToInclude(b));
void clear(Map<String, Offset> p) {
  final boxes = p.values.map((p) => p & LevelLayout.cardSize).toList();
  for (var i = 0; i < boxes.length; i++) {
    for (var j = i + 1; j < boxes.length; j++) {
      expect(boxes[i].overlaps(boxes[j]), isFalse);
    }
  }
}

Map<String, Offset> arrange(
  List<ArchitectureNode> nodes,
  List<ArchitectureEdge> edges, {
  String? anchor,
  Size viewport = const Size(1280, 800),
  bool routes = true,
  LevelLayoutMode mode = LevelLayoutMode.tidy,
}) => const LevelLayout()(
  nodes: nodes,
  edges: edges,
  rankingEdges: edges,
  viewport: viewport,
  anchorId: anchor,
  measureRoutes: routes ? measureLayoutRoutes : null,
  mode: mode,
);

void main() {
  test('SCCs and layout do not depend on node or edge insertion order', () {
    final nodes = [node('a'), node('b'), node('c'), node('input')];
    final edges = [
      edge('a', 'b'),
      edge('b', 'c'),
      edge('c', 'a'),
      edge('input', 'b'),
    ];
    final graph = LayoutGraph(
      nodes.map((n) => n.id),
      edges.map((e) => (e.from, e.to)),
    );
    expect(graph.stronglyConnected(), contains(equals(['a', 'b', 'c'])));
    final first = arrange(nodes, edges);
    expect(arrange(nodes.reversed.toList(), edges.reversed.toList()), first);
    clear(first);
  });

  test('20 disconnected cards form compact islands, not a 3576px column', () {
    final result = arrange([for (var i = 0; i < 20; i++) node('n$i')], []);
    clear(result);
    expect(bounds(result).width, lessThan(2200));
    expect(bounds(result).height, lessThan(1500));
    expect(result.values.map((p) => p.dx).toSet().length, greaterThan(1));
  });

  test('long chain can flow vertically without folding into a snake', () {
    final nodes = [for (var i = 0; i < 20; i++) node('n$i')];
    final edges = [for (var i = 0; i < 19; i++) edge('n$i', 'n${i + 1}')];
    final result = arrange(nodes, edges, viewport: const Size(900, 1100));
    expect(result.values.map((p) => p.dx).toSet(), hasLength(1));
    for (var i = 1; i < 20; i++) {
      expect(result['n$i']!.dy, greaterThan(result['n${i - 1}']!.dy));
    }
    clear(result);
  });

  test('Arrange preserves a clear horizontal sketch in a tall viewport', () {
    final nodes = [
      node('a', const Offset(0, 40)),
      node('b', const Offset(420, 0)),
      node('c', const Offset(840, 30)),
    ];
    final edges = [edge('a', 'b'), edge('b', 'c')];
    final result = arrange(nodes, edges, viewport: const Size(700, 1100));

    expect(result['a']!.dx, lessThan(result['b']!.dx));
    expect(result['b']!.dx, lessThan(result['c']!.dx));
    expect(result.values.map((p) => p.dy).toSet(), hasLength(1));
    clear(result);
  });

  test('Arrange preserves a clear vertical sketch in a wide viewport', () {
    final nodes = [
      node('a', const Offset(30, 0)),
      node('b', const Offset(0, 300)),
      node('c', const Offset(20, 600)),
    ];
    final edges = [edge('a', 'b'), edge('b', 'c')];
    final result = arrange(nodes, edges, viewport: const Size(1400, 700));

    expect(result['a']!.dy, lessThan(result['b']!.dy));
    expect(result['b']!.dy, lessThan(result['c']!.dy));
    expect(result.values.map((p) => p.dx).toSet(), hasLength(1));
    clear(result);
  });

  test('Tidy preserves human order inside a graph layer', () {
    final nodes = [
      node('source', const Offset(0, 200)),
      node('upper', const Offset(420, 0)),
      node('lower', const Offset(420, 420)),
      node('target', const Offset(840, 200)),
    ];
    final edges = [
      edge('source', 'upper'),
      edge('source', 'lower'),
      edge('upper', 'target'),
      edge('lower', 'target'),
    ];
    final result = arrange(nodes, edges);

    expect(result['upper']!.dy, lessThan(result['lower']!.dy));
    expect(result['source']!.dy, closeTo(200, .001));
    expect(result['target']!.dy, closeTo(200, .001));
    clear(result);
  });

  test('Tidy separates overlaps with the least order-preserving movement', () {
    final nodes = [
      node('source', const Offset(0, 80)),
      node('first', const Offset(420, 0)),
      node('second', const Offset(420, 30)),
      node('target', const Offset(840, 80)),
    ];
    final edges = [
      edge('source', 'first'),
      edge('source', 'second'),
      edge('first', 'target'),
      edge('second', 'target'),
    ];
    final result = arrange(nodes, edges);

    expect(result['first']!.dy, lessThan(result['second']!.dy));
    expect(
      result['second']!.dy - result['first']!.dy,
      LevelLayout.cardSize.height + 24,
    );
    clear(result);
  });

  test('Tidy evens a connected run while keeping its endpoints', () {
    final nodes = [
      node('a', const Offset(0, 20)),
      node('b', const Offset(500, 0)),
      node('c', const Offset(1120, 15)),
    ];
    final edges = [edge('a', 'b'), edge('b', 'c')];
    final result = arrange(nodes, edges);

    expect(result['a']!.dx, 0);
    expect(result['c']!.dx, 1120);
    expect(result['b']!.dx - result['a']!.dx, 560);
    expect(result['c']!.dx - result['b']!.dx, 560);
    expect(result.values.map((p) => p.dy).toSet(), hasLength(1));
    clear(result);
  });

  test('Rebuild discards coordinates and recreates ranks from connections', () {
    final nodes = [
      node('a', const Offset(0, 0)),
      node('b', const Offset(700, 300)),
      node('c', const Offset(1600, -200)),
    ];
    final edges = [edge('a', 'b'), edge('b', 'c')];
    final tidy = arrange(nodes, edges);
    final rebuilt = arrange(nodes, edges, mode: LevelLayoutMode.rebuild);

    expect(tidy['a']!.dx, 0);
    expect(tidy['c']!.dx, 1600);
    expect(rebuilt, isNot(tidy));
    expect(rebuilt['b']!.dx - rebuilt['a']!.dx, 440);
    expect(rebuilt['c']!.dx - rebuilt['b']!.dx, 440);
    expect(
      arrange(
        [for (final n in nodes) n.copyWith(position: rebuilt[n.id])],
        edges,
        mode: LevelLayoutMode.rebuild,
      ),
      rebuilt,
    );
    clear(rebuilt);
  });

  test('Tidy snaps one selected outlier to the majority rail', () {
    const rail = -278.0039255853127;
    final nodes = [
      node('a', const Offset(-963.9549132110644, rail)),
      node('b', const Offset(-523.9549132110645, rail)),
      node('c', const Offset(-83.95491321106454, rail + 50)),
    ];
    final edges = [edge('a', 'b'), edge('b', 'c')];
    final result = arrange(nodes, edges, anchor: 'c');

    expect(result['a'], nodes[0].position);
    expect(result['b'], nodes[1].position);
    expect(result['c'], const Offset(-83.95491321106454, rail));
    expect(
      arrange(
        [for (final n in nodes) n.copyWith(position: result[n.id])],
        edges,
        anchor: 'c',
      ),
      result,
    );
  });

  test('Tidy does not shelf-pack readable disconnected areas', () {
    final nodes = [
      node('a', const Offset(0, 10)),
      node('b', const Offset(430, 0)),
      node('x', const Offset(40, 620)),
      node('y', const Offset(480, 600)),
    ];
    final edges = [edge('a', 'b'), edge('x', 'y')];
    final result = arrange(nodes, edges);

    final upperCenter = (result['a']!.dy + result['b']!.dy) / 2;
    final lowerCenter = (result['x']!.dy + result['y']!.dy) / 2;
    expect(lowerCenter - upperCenter, closeTo(605, .001));
    expect(
      arrange([
        for (final n in nodes) n.copyWith(position: result[n.id]),
      ], edges),
      result,
    );
    clear(result);
  });

  test('selected card may align and repeated Tidy has no floating drift', () {
    final nodes = [
      node('a', const Offset(125.3, 290.7)),
      node('b', const Offset(850, 200)),
      node('c', const Offset(-200, 1000)),
    ];
    final edges = [edge('a', 'b'), edge('b', 'a')];
    final result = arrange(nodes, edges, anchor: 'a');
    expect(result['a']!.dx, nodes.first.position.dx);
    expect(result['a']!.dy, result['b']!.dy);
    final second = arrange(
      [for (final n in nodes) n.copyWith(position: result[n.id])],
      edges,
      anchor: 'a',
    );
    expect(second, result);
    clear(result);
  });

  test(
    'without selection preserve content center, independent of translation',
    () {
      final nodes = [
        node('a', const Offset(10000, 20000)),
        node('b', const Offset(10700, 21000)),
      ];
      final edges = [edge('a', 'b')];
      final result = arrange(nodes, edges);
      expect(
        bounds(result).center,
        bounds({for (final n in nodes) n.id: n.position}).center,
      );
      expect(
        arrange([
          for (final n in nodes) n.copyWith(position: result[n.id]),
        ], edges),
        result,
      );
    },
  );

  test('separate components reserve their actual arrow envelopes', () {
    final nodes = [
      for (final id in ['a', 'b', 'c', 'd']) node(id),
    ];
    final edges = [
      edge('a', 'b'),
      edge('b', 'a'),
      edge('c', 'd'),
      edge('d', 'c'),
    ];
    final result = arrange(nodes, edges);
    final first = measureLayoutRoutes([
      for (final n in nodes.take(2)) n.copyWith(position: result[n.id]),
    ], edges.take(2).toList());
    final second = measureLayoutRoutes([
      for (final n in nodes.skip(2)) n.copyWith(position: result[n.id]),
    ], edges.skip(2).toList());
    expect(first.bounds.overlaps(second.bounds), isFalse);
    expect(first.collisions + second.collisions, 0);
  });

  test('large graph remains deterministic and stack safe', () {
    final nodes = [for (var i = 0; i < 500; i++) node('n$i')];
    final edges = [
      for (var i = 0; i < 499; i++) edge('n$i', 'n${i + 1}'),
      edge('n499', 'n100'),
    ];
    final result = arrange(nodes, edges);
    expect(result, hasLength(500));
    expect(arrange(nodes.reversed.toList(), edges.reversed.toList()), result);
  });
}
