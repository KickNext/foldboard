import 'package:foldboard/data/repositories/board_requests_repository.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  Future<PlannerViewModel> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(
      repository: processBoard(),
      requests: BoardRequestsRepository(store: MemoryProjectStore()),
      registerBridge: false,
    );
    addTearDown(vm.repository.dispose);
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    return vm;
  }

  Future<void> traceFrom(
    WidgetTester tester,
    PlannerViewModel vm,
    String id,
  ) async {
    vm.selectCard(id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trace-selection')));
    await tester.pumpAndSettle();
  }

  testWidgets('a trace straightens the thread across every level', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    expect(find.byKey(const Key('trace-overlay')), findsOneWidget);
    // Three levels of the board, one line: no external cards stand in for the
    // parts that live somewhere else.
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'ui', 'api']);
    for (final id in ['human', 'ui', 'api']) {
      expect(find.byKey(Key('trace-card-$id')), findsOneWidget);
    }
    // The folds crossed are named above the line instead of holding the cards.
    expect(find.byKey(const Key('trace-band-app')), findsOneWidget);
    expect(find.byKey(const Key('trace-band-inner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a trace leaves the board exactly where it was', (
    tester,
  ) async {
    final vm = await mount(tester);
    vm.openLevel('app');
    await tester.pumpAndSettle();
    await traceFrom(tester, vm, 'ui');
    expect(vm.currentLevelId, 'app');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(vm.tracing, isFalse);
    expect(find.byKey(const Key('trace-overlay')), findsNothing);
    expect(vm.currentLevelId, 'app');
  });

  testWidgets('trace and overview close buttons share the right edge', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    final traceLayerRight = tester
        .getRect(find.byKey(const Key('trace-overlay')))
        .right;
    final traceRight = tester
        .getRect(find.byKey(const Key('trace-close')))
        .right;
    expect(traceRight, closeTo(traceLayerRight - 12, .01));

    await tester.tap(find.byKey(const Key('trace-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-overview')));
    await tester.pumpAndSettle();
    final overviewRight = tester
        .getRect(find.byKey(const Key('close-overview')))
        .right;
    final overviewLayerRight = tester
        .getRect(find.byKey(const Key('overview-layer')))
        .right;

    expect(traceRight, overviewRight);
    expect(overviewRight, closeTo(overviewLayerRight - 12, .01));
    await tester.tap(find.byKey(const Key('close-overview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-layer')), findsNothing);
  });

  testWidgets('trace keeps the close button on the right on a narrow screen', (
    tester,
  ) async {
    final vm = await mount(tester, size: const Size(400, 700));
    await traceFrom(tester, vm, 'human');
    final layerRight = tester
        .getRect(find.byKey(const Key('trace-overlay')))
        .right;
    final closeRight = tester
        .getRect(find.byKey(const Key('trace-close')))
        .right;

    expect(closeRight, closeTo(layerRight - 12, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a band folds its run back into one card, and back out', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    await tester.tap(find.byKey(const Key('trace-band-app')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trace-card-app')), findsOneWidget);
    expect(find.byKey(const Key('trace-card-ui')), findsNothing);
    expect(find.byKey(const Key('trace-card-api')), findsNothing);
    // The thread underneath is untouched; only what is shown changed.
    expect(vm.trace!.steps, hasLength(3));
    expect(vm.traceItems, hasLength(2));
    await tester.tap(find.byKey(const Key('trace-expand-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trace-card-ui')), findsOneWidget);
    expect(vm.traceCollapsed, isEmpty);
  });

  testWidgets('a folded card opens back up when it is tapped', (tester) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    vm.collapseTraceFold('app');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trace-card-app')));
    await tester.pumpAndSettle();
    expect(vm.traceCollapsed, isEmpty);
    expect(find.byKey(const Key('trace-card-ui')), findsOneWidget);
  });

  testWidgets('the branch it did not take is offered, and lays the thread', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    // Human continues both into the fold and straight across to the API; the
    // longer line is the thread, the other is a branch.
    expect(find.byKey(const Key('trace-branch-human')), findsOneWidget);
    await tester.tap(find.byKey(const Key('trace-branch-human')));
    await tester.pumpAndSettle();
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'api']);
    expect(vm.trace!.anchor!.id, 'api');
  });

  testWidgets('a step opens where it lives, and the trace steps aside', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    await tester.tap(find.byKey(const Key('trace-open-api')));
    await tester.pumpAndSettle();
    expect(vm.tracing, isFalse);
    expect(vm.currentLevelId, 'inner');
    expect(vm.selectedId, 'api');
  });

  testWidgets('the keyboard walks the thread and opens a step', (tester) async {
    final vm = await mount(tester);
    vm.selectCard('human');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(vm.tracing, isTrue);
    expect(vm.traceFocus, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(vm.traceFocus, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(vm.traceFocus, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(vm.tracing, isFalse);
    expect(vm.currentLevelId, 'app');
    expect(vm.selectedId, 'ui');
  });

  testWidgets('Read shows every description and edits the words in place', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trace-read-ui')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('trace-title-ui')),
      'Editor v2',
    );
    await tester.pumpAndSettle();
    expect(vm.nodes.firstWhere((n) => n.id == 'ui').title, 'Editor v2');
    // Editing a name does not rewire the thread.
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'ui', 'api']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two selected cards trace only the segment between them', (
    tester,
  ) async {
    final vm = await mount(tester);
    vm.openLevel('app');
    await tester.pumpAndSettle();
    // The fold resolves to the step the thread actually reaches inside it.
    vm.selectCards(['ui', 'inner']);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trace-selection')));
    await tester.pumpAndSettle();
    expect(vm.trace!.steps.map((s) => s.id), ['ui', 'api']);
  });

  testWidgets('cards with no thread between them say so instead of opening', (
    tester,
  ) async {
    final vm = await mount(tester);
    final stray = vm.addNode(title: 'Stray').id;
    vm.selectCards([stray, 'human']);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trace-selection')));
    await tester.pumpAndSettle();
    expect(vm.tracing, isFalse);
    expect(find.byKey(const Key('trace-overlay')), findsNothing);
    expect(vm.error, isNotNull);
  });

  testWidgets('either end of the thread can be moved to any card on the board', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'ui', 'api']);
    // The picker searches every level, so an end can sit in a fold that is not
    // the open one — which selection alone could never reach.
    await tester.tap(find.byKey(const Key('trace-end')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('board-search-dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('board-search')), 'Editor');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-result-ui')));
    await tester.pumpAndSettle();
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'ui']);
    expect(vm.tracePinnedTo, 'ui');
    // Letting the end go puts the thread back on its own sink.
    await tester.tap(find.byKey(const Key('trace-unpin-end')));
    await tester.pumpAndSettle();
    expect(vm.tracePinnedTo, isNull);
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'ui', 'api']);
  });

  testWidgets('a pinned start holds where the thread begins', (tester) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    vm.traceStartAt('ui');
    await tester.pumpAndSettle();
    expect(vm.trace!.steps.map((s) => s.id), ['ui', 'api']);
    expect(find.byKey(const Key('trace-unpin-start')), findsOneWidget);
  });

  testWidgets('one card at both ends traces its loop', (tester) async {
    final vm = await mount(tester);
    vm.repository.applyChanges({
      'edges': [
        {'id': 'api-human', 'from': 'api', 'to': 'human'},
      ],
    });
    await traceFrom(tester, vm, 'human');
    vm.startTrace(fromId: 'ui', toId: 'ui');
    await tester.pumpAndSettle();
    expect(vm.trace!.steps.map((s) => s.id), ['ui', 'api', 'human']);
    expect(vm.trace!.loopBackId, 'ui');
    expect(find.byKey(const Key('trace-loop')), findsOneWidget);
  });

  testWidgets('a card with no way back to itself says so', (tester) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    final before = vm.trace!.steps.length;
    vm.startTrace(fromId: 'ui', toId: 'ui');
    await tester.pumpAndSettle();
    expect(vm.error, isNotNull);
    expect(vm.trace!.steps, hasLength(before));
  });

  testWidgets('an edit underneath a trace re-straightens the same thread', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'human');
    vm.repository.applyChanges({
      'edges': [
        {'id': 'api-tail', 'from': 'api', 'to': 'tail'},
      ],
      'nodes': [
        {'id': 'tail', 'title': 'Tail', 'x': 1600, 'y': 300},
      ],
    });
    await tester.pumpAndSettle();
    expect(vm.trace!.steps.map((s) => s.id), ['human', 'ui', 'api', 'tail']);
    expect(find.byKey(const Key('trace-card-tail')), findsOneWidget);
  });

  testWidgets('a trace survives losing the card it was anchored on', (
    tester,
  ) async {
    final vm = await mount(tester);
    await traceFrom(tester, vm, 'ui');
    vm.repository.applyChanges({
      'deleteIds': ['ui'],
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Whatever is left of the board, the mode never shows a stale thread.
    final ids = vm.trace?.steps.map((s) => s.id) ?? const [];
    expect(ids, isNot(contains('ui')));
  });
}
