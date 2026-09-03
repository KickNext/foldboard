import 'dart:ui';

import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/domain/use_cases/auto_layout_architecture.dart';
import 'package:flutter_test/flutter_test.dart';

ArchitectureNode block(String id, [String? parent]) =>
    ArchitectureNode(id: id, title: id, parentId: parent);
ArchitectureGroup area(String id, [String? parent]) =>
    ArchitectureGroup(id: id, title: id, parentId: parent);
ArchitectureEdge arrow(String from, String to) =>
    ArchitectureEdge(id: '$from-$to', from: from, to: to);
Rect nodeRect(ArchitectureLayout layout, String id) =>
    layout.nodePositions[id]! & const Size(260, 118);

void main() {
  const arrange = AutoLayoutArchitecture();
  group('compound layout', () {
    test('external blocks align with their targets inside an area', () {
      final result = arrange(
        nodes: [
          block('human'),
          block('agent'),
          block('editor', 'app'),
          block('bridge', 'app'),
          block('graph', 'app'),
          block('export', 'app'),
        ],
        edges: [
          arrow('human', 'editor'),
          arrow('agent', 'bridge'),
          arrow('editor', 'graph'),
          arrow('bridge', 'graph'),
          arrow('graph', 'export'),
        ],
        groups: [area('app')],
      );
      for (final pair in [('human', 'editor'), ('agent', 'bridge')]) {
        expect(
          result.nodePositions[pair.$1]!.dy,
          closeTo(result.nodePositions[pair.$2]!.dy, 1),
        );
      }
      final graphY = result.nodePositions['graph']!.dy;
      final inputs = [
        result.nodePositions['editor']!.dy,
        result.nodePositions['bridge']!.dy,
      ]..sort();
      expect(graphY, greaterThan(inputs.first));
      expect(graphY, lessThan(inputs.last));
      expect(result.nodePositions['export']!.dy, closeTo(graphY, 1));
    });

    test(
      'connected sibling areas form a horizontal flow, not separate rows',
      () {
        final result = arrange(
          nodes: [block('a', 'one'), block('b', 'two')],
          edges: [arrow('a', 'b')],
          groups: [area('one'), area('two')],
        );
        expect(
          result.groupFrames['one']!.overlaps(result.groupFrames['two']!),
          isFalse,
        );
        expect(
          result.nodePositions['a']!.dy,
          closeTo(result.nodePositions['b']!.dy, 1),
        );
        expect(
          result.groupFrames['two']!.left,
          greaterThan(result.groupFrames['one']!.right),
        );
      },
    );

    test('empty sibling areas are placed and never overlap', () {
      final result = arrange(
        nodes: [],
        edges: [],
        groups: [area('one'), area('two'), area('three')],
      );
      final frames = result.groupFrames.values.toList();
      expect(frames, hasLength(3));
      for (var i = 0; i < frames.length; i++) {
        for (var j = i + 1; j < frames.length; j++) {
          expect(frames[i].overlaps(frames[j]), isFalse);
        }
      }
    });

    test('nested frames contain children and exclude unrelated siblings', () {
      final nodes = [
        block('root'),
        block('outer-node', 'outer'),
        block('inner-node', 'inner'),
        block('other-node', 'other'),
      ];
      final groups = [
        area('outer'),
        area('inner', 'outer'),
        area('empty', 'inner'),
        area('other'),
      ];
      final result = arrange(
        nodes: nodes,
        edges: [arrow('root', 'inner-node'), arrow('inner-node', 'other-node')],
        groups: groups,
      );
      for (final g in groups) {
        final frame = result.groupFrames[g.id]!;
        for (final n in nodes.where((n) => n.parentId == g.id)) {
          final r = nodeRect(result, n.id);
          expect(frame.contains(r.topLeft), isTrue);
          expect(frame.contains(r.bottomRight), isTrue);
          expect(r.top - frame.top, greaterThanOrEqualTo(48));
        }
        for (final child in groups.where((child) => child.parentId == g.id)) {
          expect(frame.contains(result.groupFrames[child.id]!.topLeft), isTrue);
          expect(
            frame.contains(result.groupFrames[child.id]!.bottomRight),
            isTrue,
          );
        }
      }
      expect(
        result.groupFrames['outer']!.overlaps(result.groupFrames['other']!),
        isFalse,
      );
      expect(
        result.groupFrames['outer']!.overlaps(nodeRect(result, 'root')),
        isFalse,
      );
    });

    test('parallel connections reorder targets to avoid simple crossings', () {
      final result = arrange(
        nodes: [block('a'), block('b'), block('c'), block('d')],
        edges: [arrow('a', 'd'), arrow('b', 'c')],
        groups: [],
      );
      expect(
        result.nodePositions['a']!.dy,
        closeTo(result.nodePositions['d']!.dy, 1),
      );
      expect(
        result.nodePositions['b']!.dy,
        closeTo(result.nodePositions['c']!.dy, 1),
      );
    });

    test('repeating arrange preserves the complete nested layout', () {
      final nodes = [block('a'), block('b', 'app'), block('c', 'inner')];
      final groups = [area('app'), area('inner', 'app'), area('empty')];
      final edges = [arrow('a', 'b'), arrow('b', 'c'), arrow('c', 'b')];
      final first = arrange(nodes: nodes, edges: edges, groups: groups);
      final second = arrange(
        nodes: [
          for (final n in nodes)
            n.copyWith(position: first.nodePositions[n.id]),
        ],
        edges: edges,
        groups: [
          for (final g in groups)
            g.copyWith(
              position: first.groupFrames[g.id]!.topLeft,
              size: first.groupFrames[g.id]!.size,
            ),
        ],
      );
      expect(second.nodePositions, first.nodePositions);
      expect(second.groupFrames, first.groupFrames);
    });
  });
}
