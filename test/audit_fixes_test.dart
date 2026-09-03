import 'dart:convert';
import 'dart:ui';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/data/repositories/board_store.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/ui/features/planner/view_models/canvas_camera.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  late ArchitectureRepository repo;
  late PlannerViewModel vm;
  setUp(() {
    repo = processBoard();
    vm = PlannerViewModel(repository: repo, registerBridge: false);
  });
  tearDown(() {
    vm.dispose();
    repo.dispose();
  });

  test('stale board cannot mutate or overwrite the newer saved board', () {
    final store = MemoryProjectStore()..value = jsonEncode(repo.snapshot());
    final a = ArchitectureRepository(store: store);
    final b = ArchitectureRepository(store: store);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.applyChanges({
      'nodes': [
        {'id': 'human', 'title': 'Tab A'},
      ],
    });
    a.flush();
    final saved = store.value;
    expect(
      () => b.applyChanges({
        'nodes': [
          {'id': 'ui', 'title': 'Tab B'},
        ],
      }),
      throwsA(isA<StorageConflict>()),
    );
    b.flush();
    expect(store.value, saved);
    expect(b.storageError, StorageFailure.conflict);
  });

  test('pending changes remain exportable when another session writes before flush', () {
    final store = MemoryProjectStore()..value = jsonEncode(repo.snapshot());
    final a = ArchitectureRepository(store: store);
    final b = ArchitectureRepository(store: store);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.applyChanges({
      'nodes': [
        {'id': 'human', 'title': 'Tab A'},
      ],
    });
    b.applyChanges({
      'nodes': [
        {'id': 'ui', 'title': 'Tab B'},
      ],
    });
    a.flush();
    final saved = store.value;
    b.flush();
    expect(store.value, saved);
    expect(b.pendingSave, isTrue);
    expect(b.nodes.firstWhere((n) => n.id == 'ui').title, 'Tab B');
    expect(b.storageError, StorageFailure.conflict);
  });

  test('stale catalog cannot drop a new project', () {
    final stores = ProjectStores();
    final a = stores.repository();
    final b = stores.repository();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final created = a.create('New');
    expect(
      () => b.rename(Project.defaultId, 'Stale rename'),
      throwsA(isA<StorageConflict>()),
    );
    final restored = stores.repository();
    addTearDown(restored.dispose);
    expect(restored.projects.any((p) => p.id == created.id), isTrue);
  });

  test('saved revision survives reopening', () {
    final store = MemoryProjectStore()
      ..value = jsonEncode({...repo.snapshot(), 'revision': 42});
    final loaded = ArchitectureRepository(store: store);
    addTearDown(loaded.dispose);
    expect(loaded.revision, 42);
    loaded.applyChanges({
      'nodes': [
        {'id': 'human', 'title': 'Next'},
      ],
    }, expectedRevision: 42);
    expect(loaded.revision, 43);
  });

  test('create and move allocate free positions', () {
    final a = vm.addNode();
    final b = vm.addNode();
    expect(
      (a.position & const Size(260, 118)).overlaps(
        b.position & const Size(260, 118),
      ),
      isFalse,
    );
    final p = vm.addGroup();
    final q = vm.addGroup();
    expect(
      (p.position & const Size(260, 118)).overlaps(
        q.position & const Size(260, 118),
      ),
      isFalse,
    );
    repo.addNode(
      const ArchitectureNode(
        id: 'moving',
        title: 'Moving',
        position: Offset(700, 300),
      ),
    );
    vm.select('moving');
    vm.moveSelectionTo('app');
    final moved = repo.nodes.firstWhere((n) => n.id == 'moving');
    final existing = repo.nodes.firstWhere((n) => n.id == 'ui');
    expect(
      (moved.position & const Size(260, 118)).overlaps(
        existing.position & const Size(260, 118),
      ),
      isFalse,
    );
  });

  test('disconnect reference preserves original and other levels, Undo restores links', () {
    vm.openLevel('inner');
    vm.selectCard('human');
    vm.deleteSelected();
    expect(repo.nodes.any((n) => n.id == 'human'), isTrue);
    expect(repo.edges.any((e) => e.id == 'human-api'), isFalse);
    expect(repo.edges.any((e) => e.id == 'human-ui'), isTrue);
    vm.undo();
    expect(repo.edges.any((e) => e.id == 'human-api'), isTrue);
    vm.redo();
    expect(repo.edges.any((e) => e.id == 'human-api'), isFalse);
  });

  test('duplicate arrow remains in drawing mode with useful message', () {
    vm.startConnection('human');
    vm.completeConnection('ui');
    expect(vm.connectFrom, 'human');
    expect(vm.warning, vm.strings.connectionExists);
    vm.cancelConnection();
    expect(vm.warning, isNull);
  });

  test(
    'drag is a single undo transaction and redo restores final position',
    () {
      final initial = repo.nodes.firstWhere((n) => n.id == 'human').position;
      repo.beginTransaction();
      for (var i = 0; i < 20; i++) {
        vm.setNodePosition('human', Offset(400 + i * 10, 100));
      }
      repo.endTransaction();
      vm.undo();
      expect(repo.nodes.firstWhere((n) => n.id == 'human').position, initial);
      vm.redo();
      expect(
        repo.nodes.firstWhere((n) => n.id == 'human').position,
        const Offset(590, 100),
      );
    },
  );

  test('typing coalesces and a new action clears redo', () {
    vm.select('human');
    final initial = vm.selectedNode!.title;
    vm.updateSelected(title: 'A');
    vm.updateSelected(title: 'AB');
    vm.updateSelected(title: 'ABC');
    vm.undo();
    expect(vm.selectedNode!.title, initial);
    expect(repo.canRedo, isTrue);
    vm.addNode();
    expect(repo.canRedo, isFalse);
  });

  test('Undo and Redo of a move follow the selected card to its level', () {
    vm.select('human');
    vm.moveSelectionTo('app');
    expect(vm.currentLevelId, 'app');
    vm.undo();
    expect(vm.currentLevelId, isNull);
    expect(vm.selectedId, 'human');
    vm.redo();
    expect(vm.currentLevelId, 'app');
    expect(vm.selectedId, 'human');
  });

  test(
    'Arrange plus manual moves preserves reference placement after reload',
    () {
      vm.openLevel('app');
      vm.autoArrange();
      final reference = vm.canvasNodes
          .firstWhere((n) => n.id == 'human')
          .position;
      vm.setNodePosition('ui', const Offset(1700, 1000));
      final store = MemoryProjectStore()..value = jsonEncode(repo.snapshot());
      final reloaded = ArchitectureRepository(store: store);
      final other = PlannerViewModel(
        repository: reloaded,
        registerBridge: false,
      )..openLevel('app');
      addTearDown(other.dispose);
      addTearDown(reloaded.dispose);
      expect(
        other.canvasNodes.firstWhere((n) => n.id == 'human').position,
        reference,
      );
    },
  );

  test('invalid import is atomic and valid import is undoable', () {
    final before = repo.snapshot();
    expect(() => vm.readImport('{bad'), throwsFormatException);
    expect(() => vm.readImport('{}'), throwsFormatException);
    expect(repo.snapshot(), before);
    final document = vm.readImport(
      '{"nodes":[{"id":"imported","title":"New"}]}',
    );
    vm.importDocument(document);
    expect(repo.nodes.single.id, 'imported');
    vm.undo();
    expect(repo.snapshot()['nodes'], before['nodes']);
    vm.redo();
    expect(repo.nodes.single.id, 'imported');
  });

  test('Fit includes very wide content with padding', () {
    final camera = CanvasCamera()..setViewport(const Size(1200, 700));
    addTearDown(camera.dispose);
    const bounds = Rect.fromLTWH(-10000, 0, 30000, 1000);
    camera.fitBounds(bounds);
    expect(camera.visibleWorldRect.contains(bounds.topLeft), isTrue);
    expect(camera.visibleWorldRect.contains(bounds.bottomRight), isTrue);
  });

  test('removing and restoring project retains exact board bytes', () {
    final stores = ProjectStores();
    final catalog = stores.repository();
    addTearDown(catalog.dispose);
    final project = catalog.create('Keep me');
    stores.board(project.boardKey).value = jsonEncode(repo.snapshot());
    final data = stores.board(project.boardKey).value;
    catalog.remove(project.id);
    expect(catalog.projects.any((p) => p.id == project.id), isFalse);
    expect(stores.board(project.boardKey).value, data);
    catalog.restore(project);
    expect(catalog.projects.any((p) => p.id == project.id), isTrue);
    expect(stores.board(project.boardKey).value, data);
  });
}
