import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;

void main() {
  Future<PlannerViewModel> mount(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(
      repository: processBoard(),
      registerBridge: false,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    return vm;
  }

  Future<void> click(WidgetTester tester, String id, int milliseconds) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.down(
      tester.getRect(find.byKey(ValueKey('node-$id'))).topLeft +
          const Offset(35, 25),
      timeStamp: Duration(milliseconds: milliseconds),
    );
    await gesture.up(timeStamp: Duration(milliseconds: milliseconds + 15));
    await tester.pump();
  }

  for (final width in [400.0, 1200.0]) {
    testWidgets(
      'single click selects, double click opens; Delete is separated at $width',
      (tester) async {
        final vm = await mount(tester, width);
        final before = vm.prettyJson;
        final cardBefore = tester.getRect(
          find.byKey(const ValueKey('node-human')),
        );
        await click(tester, 'human', 1000);
        expect(vm.selectedId, 'human');
        expect(find.byType(InspectorPanel), findsNothing);
        expect(find.byKey(const Key('delete-selection')), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        expect(find.byTooltip('Clear selection'), findsOneWidget);
        await click(tester, 'human', 1100);
        await tester.pumpAndSettle();
        expect(find.byType(InspectorPanel), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const ValueKey('node-human'))),
          cardBefore,
        );
        final remove = tester.getRect(
          find.byKey(const Key('delete-inspector')),
        );
        final close = tester.getRect(find.byTooltip('Close details'));
        expect(remove.top - close.bottom, greaterThan(200));
        expect(
          find.descendant(
            of: find.byKey(const Key('delete-inspector')),
            matching: find.text('Delete'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('delete-inspector')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close details'));
        await tester.pumpAndSettle();
        expect(find.byType(InspectorPanel), findsNothing);
        expect(vm.prettyJson, before);
        expect(
          tester.getRect(find.byKey(const ValueKey('node-human'))),
          cardBefore,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('double click enters process, slow clicks only select', (
    tester,
  ) async {
    final vm = await mount(tester, 1200);
    await click(tester, 'app', 1000);
    await click(tester, 'app', 1600);
    expect(vm.currentLevelId, isNull);
    expect(vm.selectedGroupId, 'app');
    await click(tester, 'app', 1700);
    await tester.pumpAndSettle();
    expect(vm.currentLevelId, 'app');
    expect(find.byKey(const Key('node-ui')), findsOneWidget);
    expect(find.byType(InspectorPanel), findsNothing);
  });

  testWidgets('semantic double tap enters process without pointer events', (
    tester,
  ) async {
    final vm = await mount(tester, 1200);
    void tapCard() {
      final card = tester.semantics.find(
        find.byKey(const ValueKey('node-app')),
      );
      card.owner!.performAction(card.id, SemanticsAction.tap);
    }

    tapCard();
    await tester.pump();
    tapCard();
    await tester.pumpAndSettle();

    expect(vm.currentLevelId, 'app');
    expect(find.byKey(const Key('node-ui')), findsOneWidget);
  }, semanticsEnabled: true);

  testWidgets('Clear selection works through the semantic button action', (
    tester,
  ) async {
    final vm = await mount(tester, 1200);
    vm.selectCard('human');
    await tester.pump();

    final clear = tester.semantics.find(
      find.byKey(const Key('clear-selection')),
    );
    clear.owner!.performAction(clear.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(vm.hasSelection, isFalse);
    expect(find.byTooltip('Clear selection'), findsNothing);
  }, semanticsEnabled: true);

  testWidgets(
    'double click does not enter process in hand or connection mode',
    (tester) async {
      final vm = await mount(tester, 1200);
      vm.setCanvasTool(CanvasTool.pan);
      await tester.pump();
      await click(tester, 'app', 1000);
      await click(tester, 'app', 1100);
      expect(vm.currentLevelId, isNull);
      vm.setCanvasTool(CanvasTool.select);
      vm.startConnection('human');
      await tester.pump();
      await click(tester, 'app', 2000);
      await click(tester, 'app', 2100);
      expect(vm.currentLevelId, isNull);
      expect(find.byType(InspectorPanel), findsNothing);
    },
  );
}
