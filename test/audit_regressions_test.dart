import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/data/repositories/board_store.dart';
import 'package:foldboard/data/repositories/projects_repository.dart';
import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/storage_keys.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/view_models/canvas_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  test('project IDs work with the JavaScript-safe random bound', () {
    final stores = ProjectStores();
    final repo = stores.repository();
    addTearDown(repo.dispose);
    final ids = {for (var i = 0; i < 100; i++) repo.create('Project $i').id};
    expect(ids, hasLength(100));
    expect(
      ids.every((id) => RegExp(r'^p-[0-9]+-[0-9a-f]+$').hasMatch(id)),
      isTrue,
    );
  });

  test('Undo and Redo survive project list and switching projects', () {
    final stores = ProjectStores();
    final vm = ProjectsViewModel(repository: stores.repository());
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    vm.open(Project.defaultId);
    vm.planner!.addNode(title: 'First');
    vm.showProjects();
    vm.open(Project.defaultId);
    expect(vm.planner!.repository.canUndo, isTrue);
    vm.planner!.undo();
    expect(vm.planner!.nodes, isEmpty);
    vm.create('Second');
    final second = vm.activeProject!.id;
    vm.planner!.addNode(title: 'Second card');
    vm.open(Project.defaultId);
    expect(vm.planner!.repository.canRedo, isTrue);
    vm.planner!.redo();
    expect(vm.planner!.nodes.single.title, 'First');
    vm.open(second);
    vm.planner!.undo();
    expect(vm.planner!.nodes, isEmpty);
  });

  test('history is not restored onto externally changed board bytes', () {
    final stores = ProjectStores();
    final vm = ProjectsViewModel(repository: stores.repository());
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    vm.open(Project.defaultId);
    vm.planner!.addNode(title: 'Old');
    vm.showProjects();
    stores
        .board(StorageKeys.projectBoard(Project.defaultId))
        .value = jsonEncode({
      'nodes': [
        {'id': 'external', 'title': 'External'},
      ],
    });
    vm.open(Project.defaultId);
    expect(vm.planner!.repository.canUndo, isFalse);
    expect(vm.planner!.nodes.single.title, 'External');
  });

  test(
    'read-only navigation never writes catalog and rejects board mutations',
    () {
      final stores = ProjectStores();
      final seed = processBoard();
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value =
          jsonEncode(seed.snapshot());
      seed.dispose();
      final vm = ProjectsViewModel(
        repository: ProjectsRepository(
          catalog: stores.catalog,
          boardStore: stores.board,
          initialName: 'My project',
          readOnly: true,
        ),
      );
      addTearDown(() {
        vm.dispose();
        vm.repository.dispose();
      });
      final original = stores.catalog.value;
      expect(vm.open(Project.defaultId), isTrue);
      expect(vm.planner!.nodes, isNotEmpty);
      expect(
        () => vm.planner!.repository.applyChanges({
          'deleteIds': ['human'],
        }),
        throwsA(isA<StorageConflict>()),
      );
      expect(vm.create('Not allowed'), isFalse);
      expect(vm.showProjects(), isTrue);
      expect(stores.catalog.value, original);
    },
  );

  test(
    'deleting nested processes promotes cards without collisions and can undo',
    () {
      final repo = ArchitectureRepository()
        ..replace({
          'nodes': [
            {'id': 'a', 'title': 'A', 'x': 400, 'y': 300},
            {'id': 'b', 'title': 'B', 'parentId': 'g', 'x': 400, 'y': 300},
            {'id': 'c', 'title': 'C', 'parentId': 'inner', 'x': 400, 'y': 300},
          ],
          'groups': [
            {'id': 'g', 'title': 'G', 'x': 900, 'y': 300},
            {
              'id': 'inner',
              'title': 'Inner',
              'parentId': 'g',
              'x': 400,
              'y': 300,
            },
          ],
          'edges': [
            {'id': 'ab', 'from': 'a', 'to': 'b'},
          ],
        });
      addTearDown(repo.dispose);
      repo.applyChanges({
        'deleteIds': ['g', 'inner'],
      });
      final rects = repo.nodes
          .map((n) => n.position & const Size(260, 118))
          .toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].inflate(12).overlaps(rects[j].inflate(12)), isFalse);
        }
      }
      expect(repo.nodes.every((n) => n.parentId == null), isTrue);
      expect(repo.nodes.first.position, const Offset(400, 300));
      expect(repo.edges.single.id, 'ab');
      repo.undo();
      expect(repo.groups, hasLength(2));
      expect(repo.nodes[1].parentId, 'g');
      repo.redo();
      expect(repo.groups, isEmpty);
    },
  );

  test('Fit on a huge board can zoom back in with a stable screen anchor', () {
    final camera = CanvasCamera()..setViewport(const Size(1000, 700));
    addTearDown(camera.dispose);
    camera.fitBounds(const Rect.fromLTWH(0, 0, 10000000, 700));
    final scale = camera.scale;
    const anchor = Offset(500, 350);
    final world = camera.screenToWorld(anchor);
    for (var i = 0; i < 30; i++) {
      camera.zoomBy(anchor, 1.22);
    }
    expect(camera.scale, greaterThan(scale * 100));
    expect((camera.worldToScreen(world) - anchor).distance, lessThan(.00001));
  });

  testWidgets('arrow mode stays visible after timeout and cancels explicitly', (
    tester,
  ) async {
    final vm = PlannerViewModel(
      repository: processBoard(),
      registerBridge: false,
    );
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    vm.startConnection('human');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byTooltip(vm.strings.cancelArrow), findsOneWidget);
    await tester.tap(find.byTooltip(vm.strings.cancelArrow));
    await tester.pumpAndSettle();
    expect(vm.connectFrom, isNull);
    expect(find.byKey(const Key('board-feedback')), findsNothing);
  });

  for (final size in [
    const Size(400, 360),
    const Size(400, 500),
    const Size(800, 360),
  ]) {
    testWidgets('short inspector is scrollable and avoids feedback at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vm = PlannerViewModel(
        repository: processBoard(),
        registerBridge: false,
      );
      addTearDown(() {
        vm.dispose();
        vm.repository.dispose();
      });
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      vm.selectCard('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      vm.error = 'test-error';
      vm.selectCard('human');
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(const Key('details-surface')));
      final notice = tester.getRect(find.byKey(const Key('board-feedback')));
      expect(panel.overlaps(notice), isFalse);
      expect(tester.takeException(), isNull);
      final scroll = find.byKey(const Key('short-inspector-scroll'));
      if (scroll.evaluate().isNotEmpty) {
        await tester.drag(scroll, const Offset(0, -1200));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('delete-inspector')).hitTestable(),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets(
    'read-only controls are disabled while navigation and details work',
    (tester) async {
      final stores = ProjectStores();
      final seed = processBoard();
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value =
          jsonEncode(seed.snapshot());
      seed.dispose();
      final vm = ProjectsViewModel(
        repository: ProjectsRepository(
          catalog: stores.catalog,
          boardStore: stores.board,
          initialName: 'My project',
          readOnly: true,
        ),
      );
      addTearDown(() {
        vm.dispose();
        vm.repository.dispose();
      });
      await tester.pumpWidget(FoldboardApp(projects: vm, writeAccess: false));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('new-project')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('project-${Project.defaultId}')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byKey(const Key('add-block'))).onPressed,
        isNull,
      );
      vm.planner!.selectCard('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .every((field) => field.readOnly),
        isTrue,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('delete-inspector')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
