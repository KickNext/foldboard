import 'dart:convert';

import 'package:foldboard/data/repositories/board_requests_repository.dart';
import 'package:foldboard/domain/models/agent_protocol.dart';
import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/planner/views/widgets/agent_requests_panel.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_protocol_test.dart' show call;
import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  late PlannerViewModel vm;
  late MemoryProjectStore store;
  setUp(() {
    store = MemoryProjectStore();
    vm = PlannerViewModel(
      repository: processBoard(),
      requests: BoardRequestsRepository(store: store),
      registerBridge: false,
    );
    vm.openLevel('app');
    vm.select('ui');
  });
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  test('request captures immutable selection/viewport and survives deleted targets', () {
    vm.readViewport = () => {
      'x': 1,
      'y': 2,
      'width': 500,
      'height': 300,
      'zoom': 1,
    };
    final captured = vm.captureRequestContext();
    final item = vm.requests.add('What is wrong here?', captured);
    (captured['targets'] as List).clear();
    vm.revealObject('api');
    vm.repository.applyChanges({
      'deleteIds': ['ui'],
    });
    final result = call(vm, 'get-request', {'id': item.id})['request'];
    expect(result['context']['targets'][0]['id'], 'ui');
    expect(result['context']['levelId'], 'app');
    expect(result['context']['viewport']['x'], 1);
    expect(result['missingTargetIds'], ['ui']);
    final restored = BoardRequestsRepository(store: store);
    addTearDown(restored.dispose);
    expect(restored.items.single.toJson(), item.toJson());
  });

  test(
    'lists are compact and paginated; resolving uses a separate version',
    () {
      final item = vm.requests.add(
        'Question ' * 100,
        vm.captureRequestContext(),
      );
      vm.requests.add('Second question', vm.captureRequestContext());
      final revision = vm.repository.revision;
      final list = call(vm, 'list-requests', {'limit': 1});
      expect(list['total'], 2);
      expect(list['nextOffset'], 1);
      expect(list['requests'][0]['text'].length, lessThan(250));
      expect(list['requests'][0]['textTruncated'], isTrue);
      expect(
        call(vm, 'list-requests', {
          'offset': 1,
        })['requests'][0]['textTruncated'],
        isFalse,
      );
      expect(jsonEncode(list), isNot(contains('viewport')));
      final resolved = call(vm, 'resolve-request', {
        'id': item.id,
        'expectedVersion': 1,
        'response': 'Split into two steps.',
      });
      expect(resolved['status'], 'handled');
      expect(resolved['version'], 2);
      expect(vm.repository.revision, revision);
      expect(call(vm, 'list-requests')['total'], 1);
      expect(
        call(vm, 'get-request', {'id': item.id})['request']['response'],
        'Split into two steps.',
      );
      vm.requests.reopen(item.id);
      final stale = call(vm, 'resolve-request', {
        'id': item.id,
        'expectedVersion': 1,
      });
      expect(stale['code'], 'request-conflict');
      expect(vm.requests.get(item.id).status, 'pending');
      expect(
        call(vm, 'list-requests', {'limit': 0})['code'],
        'invalid-arguments',
      );
      expect(call(vm, 'get-request', {'id': 'missing'})['code'], 'unknown-id');
    },
  );

  test(
    'agent read-only allows human requests but prevents marking handled',
    () {
      vm.agentCanWrite = () => false;
      final item = vm.requests.add('Review this', vm.captureRequestContext());
      expect(call(vm, 'get-request', {'id': item.id})['ok'], isTrue);
      expect(
        call(vm, 'resolve-request', {
          'id': item.id,
          'expectedVersion': 1,
        })['code'],
        'read-only',
      );
      expect(call(vm, 'get-user-context')['context']['pendingRequests'], 1);
    },
  );

  test('storage failure and stale writers never publish unsaved changes', () {
    final reader = BoardRequestsRepository(store: store);
    addTearDown(reader.dispose);
    store.failWrite = true;
    expect(
      () => vm.requests.add('Not saved', vm.captureRequestContext()),
      throwsA(isA<AgentException>()),
    );
    expect(vm.requests.items, isEmpty);
    store.failWrite = false;
    vm.requests.add('Saved', vm.captureRequestContext());
    expect(
      () => reader.add('Stale write', vm.captureRequestContext()),
      throwsA(isA<AgentException>()),
    );
    expect(reader.items, isEmpty);
    expect(reader.conflict, isTrue);
    final raw = store.value;
    final corrupt = BoardRequestsRepository(
      store: MemoryProjectStore()..value = '{invalid',
    );
    addTearDown(corrupt.dispose);
    expect(corrupt.loadFailed, isTrue);
    expect(corrupt.canEdit, isFalse);
    expect(store.value, raw);
  });

  test('per-project persistence is independent of board Undo/import and project switching', () {
    final projects = ProjectsViewModel(
      repository: ProjectStores().repository(),
    );
    addTearDown(() {
      projects.dispose();
      projects.repository.dispose();
    });
    projects.open(Project.defaultId);
    final first = projects.planner!;
    first.addNode(title: 'Card');
    final item = first.requests.add(
      'First project question',
      first.captureRequestContext(),
    );
    first.requests.resolve(item.id, expectedVersion: 1);
    first.undo();
    first.repository.replace({});
    expect(first.requests.get(item.id).status, 'handled');
    projects.create('Second');
    expect(projects.planner!.requests.items, isEmpty);
    projects.open(Project.defaultId);
    expect(projects.planner!.requests.get(item.id).status, 'handled');
  });

  for (final width in [400.0, 1200.0]) {
    testWidgets(
      'compose, save and handled response work without moving canvas at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(FoldboardApp(viewModel: vm));
        await tester.pumpAndSettle();
        final before = tester.getRect(find.byType(ArchitectureCanvas));
        await tester.tap(find.byKey(const Key('comment-selection')));
        await tester.pumpAndSettle();
        expect(find.text('About: Editor'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('request-text')),
          'Split this process',
        );
        // A concurrent navigation must not silently retarget this draft.
        vm.revealObject('api');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('save-request')));
        await tester.pumpAndSettle();
        final item = vm.requests.items.single;
        expect(item.targets.single['id'], 'ui');
        expect(find.text('Split this process'), findsOneWidget);
        call(vm, 'resolve-request', {
          'id': item.id,
          'expectedVersion': 1,
          'response': 'Done: two steps.',
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text('Handled'));
        await tester.pumpAndSettle();
        expect(find.text('Done: two steps.'), findsOneWidget);
        await tester.tap(find.byKey(const Key('close-agent-requests')));
        await tester.pumpAndSettle();
        expect(find.byType(AgentRequestsPanel), findsNothing);
        expect(tester.getRect(find.byType(ArchitectureCanvas)), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed save retains draft and closing requires explicit discard',
    (tester) async {
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comment-selection')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('request-text')),
        'Keep this draft',
      );
      store.failWrite = true;
      await tester.tap(find.byKey(const Key('save-request')));
      await tester.pumpAndSettle();
      expect(vm.requests.items, isEmpty);
      expect(find.text('Keep this draft'), findsOneWidget);
      await tester.tap(find.byKey(const Key('close-agent-requests')));
      await tester.pumpAndSettle();
      expect(find.text('Discard this draft?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(AgentRequestsPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compose owns focus, Escape cancels, and close restores focus', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comment-selection')));
    await tester.pumpAndSettle();

    final editor = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('request-text')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editor.focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-text')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('new-request')))
          .focusNode!
          .hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AgentRequestsPanel), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('open-agent-requests')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });
}
