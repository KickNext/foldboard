import 'package:foldboard/main.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;

void main() {
  testWidgets(
    'a changed summary is not deleted under an outdated confirmation',
    (tester) async {
      final repo = processBoard();
      final vm = PlannerViewModel(repository: repo);
      addTearDown(vm.dispose);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      vm.selectEdge(vm.canvasEdges.single.id);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      repo.addEdge(
        const ArchitectureEdge(
          id: 'added-by-agent',
          from: 'human',
          to: 'inner',
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.edges, hasLength(4));
    },
  );
  testWidgets(
    'process cards open child screens and breadcrumbs return to parent',
    (tester) async {
      final vm = PlannerViewModel(repository: processBoard());
      addTearDown(vm.dispose);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-app')), findsOneWidget);
      expect(find.byKey(const Key('node-ui')), findsNothing);
      await tester.tap(find.byKey(const Key('enter-app')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, 'app');
      expect(find.byKey(const Key('node-ui')), findsOneWidget);
      expect(find.byKey(const Key('node-inner')), findsOneWidget);
      expect(find.byKey(const Key('node-api')), findsNothing);
      expect(find.text('Input · Outside'), findsOneWidget);
      await tester.tap(find.byKey(const Key('enter-inner')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, 'inner');
      expect(find.byKey(const Key('node-api')), findsOneWidget);
      await tester.tap(find.byKey(const Key('level-up')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, 'app');
      await tester.tap(find.byKey(const Key('level-root')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outside reference navigates to the original block without changing data',
    (tester) async {
      final vm = PlannerViewModel(repository: processBoard());
      addTearDown(vm.dispose);
      vm.openLevel('app');
      final before = vm.prettyJson;
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enter-human')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, isNull);
      expect(vm.selectedId, 'human');
      expect(vm.prettyJson, before);
    },
  );

  testWidgets(
    'process editor has no area field and creates children on its own screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vm = PlannerViewModel(repository: processBoard());
      addTearDown(vm.dispose);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('node-app')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent-area')), findsNothing);
      expect(find.byType(InspectorPanel), findsOneWidget);
      await tester.tap(find.byKey(const Key('open-process')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, 'app');
      expect(find.byType(InspectorPanel), findsNothing);
      await tester.tap(find.byKey(const Key('add-block')));
      await tester.pumpAndSettle();
      expect(vm.selectedNode!.parentId, 'app');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('drawing a connection can continue after navigating up', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: processBoard());
    addTearDown(vm.dispose);
    vm.select('ui');
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connect-node')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('level-root')));
    await tester.pumpAndSettle();
    expect(vm.connectFrom, 'ui');
    await tester.tap(find.byKey(const Key('node-human')));
    await tester.pumpAndSettle();
    expect(vm.edges.any((e) => e.from == 'ui' && e.to == 'human'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
