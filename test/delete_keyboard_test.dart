import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;

void main() {
  late PlannerViewModel vm;
  setUp(() => vm = PlannerViewModel(repository: processBoard()));
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  Future<void> pressDelete(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
  }

  testWidgets('Delete confirms block deletion and can be cancelled', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('node-human')));
    await pressDelete(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(vm.nodes, hasLength(3));
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(vm.nodes, hasLength(3));
    await pressDelete(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(vm.nodes.map((n) => n.id), isNot(contains('human')));
    expect(vm.edges.map((e) => e.id), ['ui-api']);
    expect(vm.hasSelection, isFalse);
  });

  testWidgets('Delete removes process card but preserves its contents', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('node-app')));
    await pressDelete(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(vm.groups.map((g) => g.id), ['inner']);
    expect(vm.nodes, hasLength(3));
    expect(vm.nodes.firstWhere((n) => n.id == 'ui').parentId, isNull);
    expect(vm.groups.single.parentId, isNull);
  });

  testWidgets('Delete removes the selected summarized arrow only', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    vm.selectEdge(vm.canvasEdges.single.id);
    await tester.pumpAndSettle();
    await pressDelete(tester);
    expect(
      find.text('Delete all 2 connections represented by this arrow?'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(vm.edges.map((e) => e.id), ['ui-api']);
    expect(vm.nodes, hasLength(3));
    expect(vm.groups, hasLength(2));
  });

  testWidgets(
    'Delete does not remove a card while editing text, then works after canvas click',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      vm.select('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byKey(const ValueKey('title-human')),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, 'Human');
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = const TextSelection.collapsed(offset: 0);
      await pressDelete(tester);
      expect(controller.text, 'uman');
      expect(find.byType(AlertDialog), findsNothing);
      expect(vm.nodes, hasLength(3));
      await tester.enterText(field, '');
      await pressDelete(tester);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.byKey(const Key('node-human')));
      await pressDelete(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('Delete ignores empty selection, modifiers and search drawer', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await pressDelete(tester);
    expect(find.byType(AlertDialog), findsNothing);
    vm.select('human');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await pressDelete(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byKey(const Key('open-explorer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('board-search')), 'Human');
    await pressDelete(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(vm.nodes, hasLength(3));
  });

  testWidgets('Holding Delete cannot stack confirmation dialogs', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    vm.select('human');
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    await pressDelete(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(vm.nodes, hasLength(3));
  });
}
