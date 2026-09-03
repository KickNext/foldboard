import 'package:foldboard/data/repositories/board_requests_repository.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_protocol_test.dart' show call;
import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  late PlannerViewModel vm;
  setUp(() {
    vm = PlannerViewModel(
      repository: processBoard(),
      requests: BoardRequestsRepository(store: MemoryProjectStore()),
      registerBridge: false,
    );
  });
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  testWidgets('marker opens the thread beside the card; resolving clears it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-marker-human')), findsNothing);
    vm.selectCard('human');
    final item = vm.requests.add('Check this', vm.captureRequestContext());
    vm.select(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-marker-human')), findsOneWidget);
    await tester.tap(find.byKey(const Key('comment-marker-human')));
    await tester.pumpAndSettle();
    // The thread opens in place, next to the marker, not as the list panel.
    expect(find.byKey(const Key('comment-popover')), findsOneWidget);
    expect(find.byKey(const Key('requests-surface')), findsNothing);
    expect(find.text('Check this'), findsOneWidget);
    final popover = tester.getRect(find.byKey(const Key('comment-popover')));
    final marker = tester.getCenter(
      find.byKey(const Key('comment-marker-human')),
    );
    expect((popover.center - marker).distance, lessThan(360));
    // Clicking empty canvas puts the thread away.
    await tester.tapAt(const Offset(120, 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-popover')), findsNothing);
    // The list stays reachable from the thread.
    await tester.tap(find.byKey(const Key('comment-marker-human')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-requests-list')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-popover')), findsNothing);
    expect(find.byKey(const Key('requests-surface')), findsOneWidget);
    call(vm, 'resolve-request', {'id': item.id, 'expectedVersion': 1});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-marker-human')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composing highlights the anchor card until the draft ends', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    vm.selectCard('human');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comment-selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-draft-ring-human')), findsOneWidget);
    // The ring follows the captured target, not a later selection change.
    vm.select(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-draft-ring-human')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-draft-ring-human')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a request about an arrow gets a marker on the arrow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    final edge = vm.canvasEdges.first;
    vm.selectEdge(edge.id);
    await tester.pumpAndSettle();
    vm.requests.add('Explain this arrow', vm.captureRequestContext());
    vm.select(null);
    await tester.pumpAndSettle();
    final marker = find.byKey(Key('comment-marker-edge:${edge.id}'));
    expect(marker, findsOneWidget);
    await tester.tap(marker);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-popover')), findsOneWidget);
    expect(find.text('Explain this arrow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an agent answer surfaces a notice whose View opens the panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    vm.selectCard('human');
    final item = vm.requests.add('Question', vm.captureRequestContext());
    vm.select(null);
    await tester.pumpAndSettle();
    call(vm, 'resolve-request', {
      'id': item.id,
      'expectedVersion': 1,
      'response': 'All good.',
    });
    await tester.pumpAndSettle();
    expect(find.text('Agent answered a request'), findsOneWidget);
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('requests-surface')), findsOneWidget);
    expect(vm.agentRespondedRequestId, isNull);
    await tester.tap(find.text('Handled'));
    await tester.pumpAndSettle();
    expect(find.text('All good.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Details offers Ask agent while the selection bar is hidden', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    vm.selectCard('human');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comment-selection')), findsNothing);
    await tester.tap(find.byKey(const Key('comment-details')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('request-text')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('request-text')),
      'From details',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-request')));
    await tester.pumpAndSettle();
    expect(vm.requests.items.single.targets.single['id'], 'human');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arrange in canvas controls arranges the current level', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    vm.setNodePosition('human', const Offset(650, 300));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    expect(vm.arrangeVersion, 0);
    await tester.tap(find.byKey(const Key('arrange-board')));
    await tester.pumpAndSettle();
    expect(vm.arrangeVersion, 1);
    expect(tester.takeException(), isNull);
  });
}
