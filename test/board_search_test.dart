import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_board.dart';

void main() {
  late PlannerViewModel vm;
  setUp(() => vm = PlannerViewModel(repository: sampleBoard()));
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('open-explorer')));
    await tester.pumpAndSettle();
  }

  Future<void> query(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(const Key('board-search')), query);
    await tester.pumpAndSettle();
  }

  test('search filters processes, nested blocks with paths', () {
    expect(vm.searchBoard('zz-not-found'), isEmpty);
    final block = vm.searchBoard('ORDER SERVICE').first;
    expect(block.id, 'core-service');
    expect(block.path, 'Board / Sample project / Core');
    expect(
      vm.searchBoard('Sample project').any((r) => r.id == 'commerce-platform'),
      isTrue,
    );
    expect(vm.searchBoard('handles orders').single.id, 'core-service');
    expect(vm.searchBoard('   '), hasLength(5));
  });

  testWidgets(
    'search autofocus, filtering, no matches and clear work without changing board',
    (tester) async {
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      final before = vm.prettyJson;
      await openSearch(tester);
      expect(
        find.text('Type a name or description to search every level.'),
        findsOneWidget,
      );
      expect(find.text('Searches all levels'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-result-commerce-platform')),
        findsNothing,
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('board-search')),
      );
      expect(field.focusNode!.hasFocus, isTrue);
      await query(tester, 'zz-not-found');
      expect(
        find.text('No matches. Try another name or description.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('search-result-commerce-platform')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
      await query(tester, 'storage');
      expect(
        find.byKey(const ValueKey('search-result-storage')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('search-result-core-domain')),
        findsNothing,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board-search-dialog')), findsNothing);
      expect(vm.currentLevelId, isNull);
      expect(vm.prettyJson, before);
      await openSearch(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('board-search')))
            .controller!
            .text,
        isEmpty,
      );
    },
  );

  testWidgets(
    'choosing a process reveals its card rather than unexpectedly entering it',
    (tester) async {
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await openSearch(tester);
      await query(tester, 'Core');
      await tester.tap(find.byKey(const ValueKey('search-result-core-domain')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, 'commerce-platform');
      expect(vm.selectedGroupId, 'core-domain');
      expect(vm.cameraTargetId, 'core-domain');
      expect(find.byKey(const Key('board-search-dialog')), findsNothing);
      final canvas = tester.getRect(find.byType(ArchitectureCanvas));
      final card = tester.getRect(
        find.byKey(const ValueKey('node-core-domain')),
      );
      expect(canvas.contains(card.center), isTrue);
      expect(find.byType(InspectorPanel), findsNothing);
    },
  );

  testWidgets('Ctrl+F opens search, arrows change result and Enter navigates', (
    tester,
  ) async {
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('board-search-dialog')), findsOneWidget);
    await query(tester, 'core');
    final second = vm.searchBoard('core')[1];
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('board-search-dialog')), findsNothing);
    expect(vm.selectedId, second.id);
    expect(vm.currentLevelId, 'core-domain');
    expect(vm.cameraTargetId, second.id);
  });

  testWidgets(
    'large search renders a lazy list and stays usable on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      vm.repository.applyChanges({
        'nodes': [
          for (var i = 0; i < 1000; i++)
            {'id': 'many-$i', 'title': 'Result $i', 'x': i * 400, 'y': 200},
        ],
      });
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await openSearch(tester);
      await query(tester, 'Result');
      expect(
        find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith(
                    'search-result-',
                  ),
            )
            .evaluate()
            .length,
        lessThan(20),
      );
      await query(tester, 'Result 999');
      await tester.tap(find.byKey(const ValueKey('search-result-many-999')));
      await tester.pumpAndSettle();
      expect(vm.selectedId, 'many-999');
      expect(tester.takeException(), isNull);
    },
  );
}
