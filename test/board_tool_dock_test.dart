import 'package:foldboard/main.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/data/repositories/board_requests_repository.dart';
import 'package:foldboard/ui/features/planner/views/planner_page.dart';
import 'package:foldboard/ui/core/write_access_scope.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  Future<PlannerViewModel> mount(WidgetTester tester, Size size) async {
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

  for (final width in [320.0, 400.0, 660.0, 800.0, 1200.0]) {
    testWidgets('dock, zoom and details remain separate at $width', (
      tester,
    ) async {
      final vm = await mount(tester, Size(width, 800));
      final dock = tester.getRect(find.byKey(const Key('board-tool-dock')));
      final controls = tester.getRect(find.byKey(const Key('zoom-controls')));
      expect(dock.left, greaterThanOrEqualTo(0));
      expect(dock.right, lessThanOrEqualTo(width));
      expect(dock.bottom, closeTo(784, .01));
      expect(dock.overlaps(controls), isFalse);
      expect(find.byKey(const Key('add-block')), findsOneWidget);
      expect(find.byKey(const Key('undo')), findsOneWidget);
      expect(find.byKey(const Key('redo')), findsOneWidget);
      expect(find.byKey(const Key('dock-history')), findsNothing);
      final history = tester.getRect(find.byKey(const Key('board-history')));
      expect(history.left, 14);
      expect(history.bottom, lessThan(190));
      expect(history.overlaps(dock), isFalse);
      expect(
        dock.contains(tester.getCenter(find.byKey(const Key('add-process')))),
        isTrue,
      );
      // Layout commands live with the canvas view controls instead of reading
      // as extra steps in the level path.
      if (width >= 660) {
        expect(find.byKey(const Key('arrange-board')), findsOneWidget);
        expect(find.byKey(const Key('rebuild-board')), findsOneWidget);
        expect(
          controls.contains(
            tester.getCenter(find.byKey(const Key('arrange-board'))),
          ),
          isTrue,
        );
      } else {
        expect(find.byKey(const Key('arrange-board')), findsNothing);
        expect(find.byKey(const Key('rebuild-board')), findsNothing);
      }
      expect(find.byKey(const Key('open-agent-requests')), findsOneWidget);
      vm.selectCard('human');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      final details = tester.getRect(find.byKey(const Key('details-surface')));
      expect(details.overlaps(dock), isFalse);
      expect(details.overlaps(controls), isFalse);
      expect(tester.getRect(find.byKey(const Key('board-tool-dock'))), dock);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('hand mode and scrolling over tools do not move the canvas', (
    tester,
  ) async {
    final vm = await mount(tester, const Size(1200, 800));
    await tester.tap(find.byKey(const Key('tool-pan')));
    await tester.pumpAndSettle();
    expect(vm.canvasTool, CanvasTool.pan);
    final before = vm.readViewport!();
    final position = tester.getCenter(find.byKey(const Key('tool-pan')));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: position, scrollDelta: const Offset(0, 120)),
    );
    await tester.pumpAndSettle();
    expect(vm.readViewport!(), before);
    await tester.drag(find.byKey(const Key('tool-pan')), const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(vm.readViewport!(), before);
    await tester.tap(find.byKey(const Key('tool-select')));
    await tester.pumpAndSettle();
    expect(vm.canvasTool, CanvasTool.select);
    expect(tester.takeException(), isNull);
  });

  for (final item in [
    (key: 'add-block', process: false),
    (key: 'add-process', process: true),
  ]) {
    testWidgets(
      'new ${item.process ? 'process' : 'block'} opens a focused blank name',
      (tester) async {
        final vm = await mount(tester, const Size(1200, 800));
        await tester.tap(find.byKey(Key(item.key)));
        await tester.pumpAndSettle();

        final id = item.process ? vm.selectedGroupId! : vm.selectedId!;
        expect(
          item.process ? vm.selectedGroup!.title : vm.selectedNode!.title,
          isEmpty,
        );
        expect(find.byKey(const Key('details-surface')), findsOneWidget);
        final name = find.descendant(
          of: find.byKey(ValueKey('title-$id')),
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(name).controller!.text, isEmpty);
        final editable = tester.widget<EditableText>(
          find.descendant(of: name, matching: find.byType(EditableText)),
        );
        expect(editable.focusNode.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('compact canvas menu retains layout, zoom and fit commands', (
    tester,
  ) async {
    final vm = await mount(tester, const Size(400, 800));
    vm.setNodePosition('human', const Offset(650, 300));
    await tester.pumpAndSettle();
    final before = vm.readViewport!()['zoom'];
    await tester.tap(find.byKey(const Key('zoom-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Tidy'), findsOneWidget);
    expect(find.text('Rebuild layout'), findsOneWidget);
    expect(find.text('Fit content'), findsOneWidget);
    await tester.tap(find.text('Tidy'));
    await tester.pumpAndSettle();
    expect(vm.arrangeVersion, 1);
    await tester.tap(find.byKey(const Key('zoom-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zoom in'));
    await tester.pumpAndSettle();
    expect(vm.readViewport!()['zoom'], greaterThan(before as num));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tidy and Rebuild are two direct layout actions', (tester) async {
    await mount(tester, const Size(1200, 800));
    final controls = tester.getRect(find.byKey(const Key('zoom-controls')));
    expect(find.byKey(const Key('arrange-board')), findsOneWidget);
    expect(find.byKey(const Key('rebuild-board')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('level-path')),
        matching: find.byKey(const Key('arrange-board')),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('arrange-board')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('rebuild-board')))
          .onPressed,
      isNotNull,
    );
    expect(
      controls.contains(
        tester.getCenter(find.byKey(const Key('arrange-board'))),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('comment without selection captures the current level', (
    tester,
  ) async {
    final vm = await mount(tester, const Size(400, 800));
    vm.openLevel('app');
    await tester.pumpAndSettle();
    expect(vm.hasSelection, isFalse);
    final before = vm.prettyJson;
    await tester.tap(find.byKey(const Key('open-agent-requests')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-request')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('request-text')),
      'Review this level',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-request')));
    await tester.pumpAndSettle();
    final item = vm.requests.items.single;
    expect(item.targets, isEmpty);
    expect(item.context['levelId'], 'app');
    expect(vm.prettyJson, before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history is one click and read-only disables writes', (
    tester,
  ) async {
    final vm = await mount(tester, const Size(1200, 800));
    final before = vm.nodes.length;
    vm.addNode(title: 'Temporary');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('undo')));
    await tester.pumpAndSettle();
    expect(vm.nodes.length, before);
    await tester.tap(find.byKey(const Key('redo')));
    await tester.pumpAndSettle();
    expect(vm.nodes.length, before + 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WriteAccessScope(
          canWrite: false,
          child: PlannerPage(viewModel: vm),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in ['undo', 'redo']) {
      expect(tester.widget<IconButton>(find.byKey(Key(key))).onPressed, isNull);
    }
    for (final key in ['arrange-board', 'rebuild-board']) {
      expect(tester.widget<IconButton>(find.byKey(Key(key))).onPressed, isNull);
    }
    expect(
      tester.widget<TextButton>(find.byKey(const Key('add-block'))).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byKey(const Key('tool-pan'))).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
