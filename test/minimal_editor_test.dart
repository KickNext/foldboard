import 'package:foldboard/main.dart';
import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_board.dart';

Finder editor(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('empty mobile board starts centred at 100% zoom', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: ArchitectureRepository());
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();

    final viewport = vm.readViewport!();
    expect(viewport['zoom'], 1);
    expect(
      (viewport['x'] as num) + (viewport['width'] as num) / 2,
      closeTo(0, .001),
    );
    expect(
      (viewport['y'] as num) + (viewport['height'] as num) / 2,
      closeTo(0, .001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('draws a plain arrow by choosing two blocks', (tester) async {
    final repo = sampleBoard();
    final vm = PlannerViewModel(repository: repo);
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    vm.select('web-client');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pumpAndSettle();
    final connect = find.byKey(const Key('connect-node'));
    await tester.scrollUntilVisible(
      connect,
      160,
      scrollable: find
          .descendant(
            of: find.byType(InspectorPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.byType(InspectorPanel), findsNothing);
    expect(vm.connectFrom, 'web-client');
    await tester.tap(find.byTooltip('Fit content'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('node-storage')));
    await tester.pumpAndSettle();
    expect(
      vm.edges.where((e) => e.from == 'web-client' && e.to == 'storage'),
      hasLength(1),
    );
    expect(vm.connectFrom, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty board creates a plain block with one description', (
    tester,
  ) async {
    final vm = PlannerViewModel(repository: ArchitectureRepository());
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('empty-board')), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-block')));
    await tester.pumpAndSettle();
    final id = vm.nodes.single.id;
    expect(find.byType(InspectorPanel), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.enterText(editor('title-$id'), 'Editor');
    await tester.enterText(
      editor('description-$id'),
      'A shared description for a person and an agent',
    );
    await tester.pumpAndSettle();
    expect(vm.nodes.single.title, 'Editor');
    expect(
      vm.nodes.single.description,
      'A shared description for a person and an agent',
    );
    expect(
      vm.snapshot()['nodes'].single.keys,
      unorderedEquals(['id', 'title', 'description', 'x', 'y', 'parentId']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'arrow deletion is explicit, cancellable and does not delete blocks',
    (tester) async {
      final vm = PlannerViewModel(repository: sampleBoard());
      addTearDown(vm.dispose);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      vm.selectEdge('ui-core');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('open-details')), findsNothing);
      expect(find.byKey(const Key('delete-selection')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(vm.edges, hasLength(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(vm.edges, hasLength(1));
      expect(vm.nodes, hasLength(3));
      expect(vm.selectedEdgeId, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
