import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/planner_page.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  late PlannerViewModel vm;
  setUp(
    () => vm = PlannerViewModel(
      repository: processBoard(),
      registerBridge: false,
    ),
  );
  tearDown(() => {vm.dispose(), vm.repository.dispose()});

  Future<void> mount(WidgetTester tester, {double width = 1200}) async {
    await tester.binding.setSurfaceSize(Size(width, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
  }

  for (final width in [400.0, 1200.0]) {
    testWidgets('feedback never shifts the board at $width', (tester) async {
      vm.openLevel('app');
      await mount(tester, width: width);
      final board = find.byKey(const ValueKey('planner-board'));
      final card = find.byKey(const Key('node-ui'));
      final boardRect = tester.getRect(board);
      final cardRect = tester.getRect(card);
      final before = vm.prettyJson;

      void expectStable() {
        expect(tester.getRect(board), boardRect);
        expect(tester.getRect(card), cardRect);
        expect(vm.prettyJson, before);
        expect(tester.takeException(), isNull);
      }

      vm.startConnection('human');
      await tester.pumpAndSettle();
      expectStable();
      vm.completeConnection('ui');
      await tester.pumpAndSettle();
      expect(find.text(vm.strings.connectionExists), findsOneWidget);
      expect(find.text(vm.strings.connectFromPrompt('Human')), findsNothing);
      expectStable();
      final feedback = tester.getRect(find.byKey(const Key('board-feedback')));
      expect(feedback.center.dx, closeTo(boardRect.center.dx, .01));
      expect(feedback.top, boardRect.top + 80);
      expect(feedback.bottom, lessThanOrEqualTo(boardRect.top + 156));
      expect(
        feedback.overlaps(
          tester.getRect(find.byKey(const Key('board-tool-dock'))),
        ),
        isFalse,
      );

      await tester.tap(find.byKey(const Key('dismiss-board-feedback')));
      await tester.pumpAndSettle();
      expect(vm.connectFrom, 'human');
      expect(find.text(vm.strings.connectFromPrompt('Human')), findsOneWidget);
      expect(find.byTooltip(vm.strings.cancelArrow), findsOneWidget);
      expectStable();

      vm.completeConnection('ui');
      await tester.pumpAndSettle();
      expect(find.text(vm.strings.connectionExists), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('board-feedback')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(vm.strings.connectFromPrompt('Human')), findsOneWidget);
      expect(vm.connectFrom, 'human');
      expectStable();
      vm.cancelConnection();

      vm.error = 'test-error';
      vm.selectCard('ui');
      await tester.pumpAndSettle();
      expect(find.text(vm.strings.changeFailed), findsOneWidget);
      expectStable();
      await tester.tap(find.byKey(const Key('dismiss-board-feedback')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board-feedback')), findsNothing);
      expectStable();
    });

    testWidgets('notification avoids the open inspector at $width', (
      tester,
    ) async {
      await mount(tester, width: width);
      vm.selectCard('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      vm.error = 'test-error';
      vm.selectCard('human');
      await tester.pumpAndSettle();
      final feedback = tester.getRect(find.byKey(const Key('board-feedback')));
      expect(
        feedback.overlaps(
          tester.getRect(find.byKey(const Key('details-surface'))),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('board-feedback')), findsNothing);
    });

    testWidgets('quick connection and pointer delete work at $width', (
      tester,
    ) async {
      await mount(tester, width: width);
      vm.select('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draw-selected-arrow')));
      await tester.pumpAndSettle();
      expect(vm.connectFrom, 'human');
      expect(find.byType(InspectorPanel), findsNothing);
      vm.cancelConnection();
      vm.selectEdge(vm.canvasEdges.first.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('arrow-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(vm.edges.map((e) => e.id), ['ui-api']);
      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(vm.edges.length, 3);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'reference delete confirms disconnection and preserves original',
    (tester) async {
      vm.openLevel('inner');
      await mount(tester);
      vm.selectCard('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      expect(find.text(vm.strings.referenceHint), findsOneWidget);
      expect(find.byKey(const Key('move-level')), findsNothing);
      await tester.tap(find.byKey(const Key('delete-inspector')));
      await tester.pumpAndSettle();
      expect(find.text(vm.strings.disconnectHint), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(vm.nodes.any((n) => n.id == 'human'), isTrue);
      expect(vm.edges.any((e) => e.id == 'human-ui'), isTrue);
      expect(vm.edges.any((e) => e.id == 'human-api'), isFalse);
    },
  );

  testWidgets('Tab focuses cards, arrows move and Enter opens details', (
    tester,
  ) async {
    await mount(tester);
    var reached = false;
    for (var i = 0; i < 40; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus?.context;
      focused?.visitAncestorElements((element) {
        if (element.widget.key == const Key('node-human')) reached = true;
        return true;
      });
      if (reached) break;
    }
    expect(reached, isTrue);
    final before = vm.nodes.firstWhere((n) => n.id == 'human').position;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      vm.nodes.firstWhere((n) => n.id == 'human').position,
      before + const Offset(10, 0),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(InspectorPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real pointer drag undoes in one step through keyboard shortcut',
    (tester) async {
      await mount(tester);
      final before = vm.nodes.firstWhere((n) => n.id == 'human').position;
      final card = find.byKey(const Key('node-human'));
      final drag = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(40, 0));
      await tester.pump();
      await drag.moveBy(const Offset(40, 40));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(
        vm.nodes.firstWhere((n) => n.id == 'human').position,
        isNot(before),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(vm.nodes.firstWhere((n) => n.id == 'human').position, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'import previews, cancel preserves board, confirm supports Undo',
    (tester) async {
      const imported = '{"nodes":[{"id":"imported","title":"Imported"}]}';
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlannerPage(viewModel: vm, pickJson: () async => imported),
        ),
      );
      await tester.pumpAndSettle();
      final before = vm.prettyJson;
      Future<void> open() async {
        await tester.tap(find.byKey(const Key('board-more')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Import JSON'));
        await tester.pumpAndSettle();
      }

      await open();
      expect(find.text(vm.strings.importTitle), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(vm.prettyJson, before);
      await open();
      await tester.tap(find.widgetWithText(FilledButton, 'Import JSON'));
      await tester.pumpAndSettle();
      expect(vm.nodes.single.id, 'imported');
      await tester.tap(find.byKey(const Key('undo')));
      await tester.pumpAndSettle();
      expect(vm.nodes.length, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('project removal can be restored from snackbar', (tester) async {
    final stores = ProjectStores();
    final projects = ProjectsViewModel(repository: stores.repository());
    addTearDown(projects.dispose);
    addTearDown(projects.repository.dispose);
    await tester.pumpWidget(FoldboardApp(projects: projects));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('project-actions-${Project.defaultId}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove project'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove project'));
    await tester.pumpAndSettle();
    expect(projects.projects, isEmpty);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(projects.projects.single.id, Project.defaultId);
  });
}
