import 'support/sample_board.dart';

import 'dart:ui';

import 'package:foldboard/domain/use_cases/auto_layout_architecture.dart';

import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feedback loops do not collapse the graph into a column', () {
    final repository = sampleBoard()..clear();
    for (var i = 0; i < 5; i++) {
      repository.addNode(
        ArchitectureNode(id: 'n$i', title: 'Node $i', position: Offset.zero),
      );
    }
    for (final pair in [(0, 1), (1, 2), (2, 3), (3, 1), (2, 4)]) {
      repository.addEdge(
        ArchitectureEdge(
          id: '${pair.$1}-${pair.$2}',
          from: 'n${pair.$1}',
          to: 'n${pair.$2}',
        ),
      );
    }
    final vm = PlannerViewModel(repository: repository);
    vm.autoArrange();
    expect(
      repository.nodes.map((n) => n.position.dx).toSet().length,
      greaterThan(2),
    );
    expect(repository.nodes.map((n) => n.position).toSet().length, 5);
    expect(repository.edges.length, 5);
    final first = repository.nodes.map((n) => n.position).toList();
    vm.autoArrange();
    expect(repository.nodes.map((n) => n.position).toList(), first);
  });

  test('sibling boundaries do not overlap', () {
    final repository = sampleBoard()..clear();
    for (final id in ['a', 'b']) {
      repository.addGroup(
        ArchitectureGroup(
          id: id,
          title: id,
          position: Offset.zero,
          size: const Size(500, 300),
        ),
      );
      for (var i = 0; i < 2; i++) {
        repository.addNode(
          ArchitectureNode(
            id: '$id$i',
            title: '$id$i',
            position: Offset.zero,
            parentId: id,
          ),
        );
      }
    }
    repository.addEdge(
      const ArchitectureEdge(id: 'cross', from: 'a0', to: 'b1'),
    );
    final layout = const AutoLayoutArchitecture()(
      nodes: repository.nodes,
      edges: repository.edges,
      groups: repository.groups,
    );
    repository.applyLayout(
      nodePositions: layout.nodePositions,
      groupFrames: layout.groupFrames,
    );
    final a = repository.groups[0];
    final b = repository.groups[1];
    expect((a.position & a.size).overlaps(b.position & b.size), isFalse);
  });
  test('auto arrange follows graph direction and wraps boundaries', () {
    final repository = sampleBoard();
    final layout = const AutoLayoutArchitecture()(
      nodes: repository.nodes,
      edges: repository.edges,
      groups: repository.groups,
    );
    repository.applyLayout(
      nodePositions: layout.nodePositions,
      groupFrames: layout.groupFrames,
    );

    for (final edge in repository.edges) {
      final from = repository.nodes
          .where((node) => node.id == edge.from)
          .single;
      final to = repository.nodes.where((node) => node.id == edge.to).single;
      // Keep a clear arrow corridor, without requiring the old oversized grid.
      expect(
        to.position.dx - (from.position.dx + 260),
        greaterThanOrEqualTo(180),
      );
    }

    final core = repository.groups
        .where((group) => group.id == 'core-domain')
        .single;
    final coreRect = core.position & core.size;
    for (final node in repository.nodes.where(
      (node) => node.parentId == core.id,
    )) {
      expect(coreRect.contains(node.position), isTrue);
    }
  });
}
