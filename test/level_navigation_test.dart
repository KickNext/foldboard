import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/view_models/level_graph.dart';
import 'package:flutter_test/flutter_test.dart';

ArchitectureRepository processBoard() => ArchitectureRepository()
  ..replace({
    'groups': [
      {'id': 'app', 'title': 'App', 'x': 700, 'y': 300},
      {'id': 'inner', 'title': 'Inner', 'parentId': 'app', 'x': 1200, 'y': 300},
    ],
    'nodes': [
      {'id': 'human', 'title': 'Human', 'x': 200, 'y': 300},
      {'id': 'ui', 'title': 'Editor', 'parentId': 'app', 'x': 700, 'y': 300},
      {'id': 'api', 'title': 'API', 'parentId': 'inner', 'x': 1200, 'y': 300},
    ],
    'edges': [
      {'id': 'human-ui', 'from': 'human', 'to': 'ui'},
      {'id': 'ui-api', 'from': 'ui', 'to': 'api'},
      {'id': 'human-api', 'from': 'human', 'to': 'api'},
    ],
  });

void main() {
  late ArchitectureRepository repo;
  late PlannerViewModel vm;
  setUp(() {
    repo = processBoard();
    vm = PlannerViewModel(repository: repo);
  });
  tearDown(() {
    vm.dispose();
    repo.dispose();
  });

  test('root hides descendants and summarizes their external connections', () {
    expect(vm.canvasNodes.map((n) => n.id), unorderedEquals(['human', 'app']));
    expect(vm.canvasEdges, hasLength(1));
    expect(vm.canvasEdges.single.to, 'app');
    expect(vm.levelGraph.edgeSources.values.single, ['human-ui', 'human-api']);
    expect(repo.edges, hasLength(3));
  });
  test('nested level shows reference cards without duplicating data', () {
    final before = vm.prettyJson;
    vm.openLevel('app');
    expect(
      vm.canvasNodes.map((n) => n.id),
      unorderedEquals(['ui', 'inner', 'human']),
    );
    expect(vm.levelGraph.referenceIds, {'human'});
    vm.openLevel('inner');
    expect(
      vm.canvasNodes.map((n) => n.id),
      unorderedEquals(['api', 'ui', 'human']),
    );
    expect(vm.levelPath.map((g) => g.id), ['app', 'inner']);
    vm.revealObject('ui');
    expect(vm.currentLevelId, 'app');
    expect(vm.selectedId, 'ui');
    expect(vm.prettyJson, before);
  });
  test('new blocks and processes belong to the current level', () {
    vm.openLevel('inner');
    expect(vm.addNode().parentId, 'inner');
    expect(vm.addGroup().parentId, 'inner');
  });
  test('arrange and card dragging leave child levels and external sources untouched', () {
    final children = repo.nodes
        .where((n) => n.parentId != null)
        .map((n) => n.toJson())
        .toList();
    vm.setNodePosition('app', const Offset(900, 800));
    vm.autoArrange();
    expect(
      repo.nodes
          .where((n) => n.parentId != null)
          .map((n) => n.toJson())
          .toList(),
      children,
    );
    vm.openLevel('inner');
    final human = repo.nodes.firstWhere((n) => n.id == 'human').position;
    vm.autoArrange();
    vm.setNodePosition('human', const Offset(-50, -50));
    expect(repo.nodes.firstWhere((n) => n.id == 'human').position, human);
    final positions = vm.canvasNodes.map((n) => n.position).toList();
    vm.autoArrange();
    expect(vm.canvasNodes.map((n) => n.position).toList(), positions);
  });
  test('agent Tidy of a non-current nested level is stable', () {
    expect(vm.currentLevelId, isNull);
    repo.addNode(const ArchitectureNode(id: 'before', title: 'Before'));
    repo.addNode(const ArchitectureNode(id: 'after', title: 'After'));
    repo.addEdge(
      const ArchitectureEdge(id: 'before-app', from: 'before', to: 'app'),
    );
    repo.addEdge(
      const ArchitectureEdge(id: 'app-after', from: 'app', to: 'after'),
    );

    vm.autoArrange(levelId: 'app', useCurrentLevel: false);
    final first = jsonEncode(repo.snapshot());
    vm.autoArrange(levelId: 'app', useCurrentLevel: false);

    expect(jsonEncode(repo.snapshot()), first);
  });
  test('connection can cross levels and can target a process card', () {
    vm.startConnection('ui');
    vm.openLevel(null);
    expect(vm.connectFrom, 'ui');
    vm.selectCard('human');
    expect(repo.edges.any((e) => e.from == 'ui' && e.to == 'human'), isTrue);
    expect(
      repo.addEdge(
        const ArchitectureEdge(id: 'process-edge', from: 'app', to: 'human'),
      ),
      isTrue,
    );
    vm.openLevel('app');
    expect(vm.levelGraph.referenceIds, isNot(contains('app')));
    expect(vm.canvasNodes.map((n) => n.id), isNot(contains('app')));
    expect(vm.canvasNodes.map((n) => n.id), contains('human'));
    expect(vm.levelGraph.referenceFlows['human'], ReferenceFlow.both);
    expect(vm.levelGraph.referenceSources['human'], ['process-edge']);
  });
  test(
    'direct process input is a usable external reference, not a self card',
    () {
      repo.replace({
        'groups': [
          {'id': 'app', 'title': 'App'},
        ],
        'nodes': [
          {'id': 'outside', 'title': 'Outside'},
          {'id': 'receiver', 'title': 'Receiver'},
          {'id': 'inside', 'title': 'Inside', 'parentId': 'app'},
        ],
        'edges': [
          {'id': 'outside-app', 'from': 'outside', 'to': 'app'},
          {'id': 'app-receiver', 'from': 'app', 'to': 'receiver'},
        ],
      });
      vm.openLevel('app');

      expect(
        vm.canvasNodes.map((n) => n.id),
        unorderedEquals(['inside', 'outside', 'receiver']),
      );
      expect(vm.levelGraph.referenceIds, {'outside', 'receiver'});
      expect(vm.levelGraph.referenceFlows['outside'], ReferenceFlow.input);
      expect(vm.levelGraph.referenceFlows['receiver'], ReferenceFlow.output);
      expect(vm.levelGraph.referenceSources['outside'], ['outside-app']);
      expect(vm.levelGraph.referenceSources['receiver'], ['app-receiver']);
      expect(vm.canvasEdges, isEmpty);

      vm.autoArrange();
      final arranged = {
        for (final node in vm.canvasNodes) node.id: node.position,
      };
      expect(arranged.values.toSet(), hasLength(3));

      const customPosition = Offset(900, -100);
      final originalPosition = repo.nodes
          .firstWhere((node) => node.id == 'outside')
          .position;
      vm.setNodePosition('outside', customPosition);
      expect(
        vm.canvasNodes.firstWhere((node) => node.id == 'outside').position,
        customPosition,
      );
      expect(
        repo.nodes.firstWhere((node) => node.id == 'outside').position,
        originalPosition,
      );
      expect(repo.referencePositions('app')['outside'], customPosition);

      vm.selectCard('outside');
      expect(vm.referenceConnectionIds, ['outside-app']);

      vm.startConnection('outside');
      vm.selectCard('inside');
      expect(
        repo.edges.any((edge) => edge.from == 'outside' && edge.to == 'inside'),
        isTrue,
      );
    },
  );
  test(
    'deleting a summarized arrow deletes exactly the confirmed source edges',
    () {
      vm.selectEdge(vm.canvasEdges.single.id);
      expect(vm.selectedConnectionIds, hasLength(2));
      vm.deleteSelected();
      expect(repo.edges.map((e) => e.id), ['ui-api']);
      expect(repo.nodes, hasLength(3));
    },
  );
  test('deleted current level returns to root and keeps its contents', () {
    vm.openLevel('inner');
    repo.applyChanges({
      'deleteIds': ['inner'],
    });
    expect(vm.currentLevelId, isNull);
    expect(repo.nodes.firstWhere((n) => n.id == 'api').parentId, 'app');
  });
  test(
    'agent reads and exports process endpoints with no synthetic objects',
    () {
      repo.addEdge(
        const ArchitectureEdge(id: 'process-edge', from: 'inner', to: 'human'),
      );
      final result = vm.handleTool('get-area', {
        'id': 'inner',
        'return': 'full',
        'includeView': true,
      });
      expect(result['ok'], isTrue);
      final imported = ArchitectureRepository()
        ..replace(Map<String, dynamic>.from(result['area'] as Map));
      expect(imported.edges.any((e) => e.id == 'process-edge'), isTrue);
      expect((result['view'] as Map)['levelId'], 'inner');
      expect(vm.currentLevelId, isNull);
      imported.dispose();
    },
  );
}
