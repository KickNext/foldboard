import 'package:foldboard/app_info.dart';
import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/data/repositories/settings_repository.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/core/shortcuts_dialog.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/settings/view_models/settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/project_stores.dart';
import 'support/sample_board.dart';

void main() {
  Future<PlannerViewModel> pumpBoard(
    WidgetTester tester, {
    ArchitectureRepository? repository,
    SettingsViewModel? settings,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vm = PlannerViewModel(
      repository: repository ?? ArchitectureRepository(),
    );
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(FoldboardApp(viewModel: vm, settings: settings));
    await tester.pumpAndSettle();
    return vm;
  }

  testWidgets('the empty board offers both primitives', (tester) async {
    final vm = await pumpBoard(tester);
    expect(find.byKey(const Key('empty-board')), findsOneWidget);

    await tester.tap(find.byKey(const Key('empty-add-process')));
    await tester.pumpAndSettle();
    expect(vm.groups.single.parentId, isNull);
    expect(vm.selectedGroupId, vm.groups.single.id);
    expect(find.byKey(const Key('empty-board')), findsNothing);
  });

  testWidgets('a read-only board explains itself without offering actions', (
    tester,
  ) async {
    await pumpBoard(tester, repository: ArchitectureRepository(readOnly: true));
    expect(find.byKey(const Key('empty-board')), findsOneWidget);
    expect(find.byKey(const Key('empty-add-block')), findsNothing);
  });

  testWidgets('? opens the shortcut reference and Close dismisses it', (
    tester,
  ) async {
    await pumpBoard(tester, repository: sampleBoard());
    // The harness has no physical key for '?'; send the character instead.
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keyboard-shortcuts-dialog')), findsOneWidget);
    expect(find.text('Search every level'), findsOneWidget);
    expect(find.text('Paste into this level'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(KeyboardShortcutsDialog), findsNothing);
  });

  testWidgets('More actions reaches the same reference', (tester) async {
    await pumpBoard(tester, repository: sampleBoard());
    await tester.tap(find.byKey(const Key('board-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-shortcuts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keyboard-shortcuts-dialog')), findsOneWidget);
  });

  testWidgets('the More menu opens the shortcut reference', (tester) async {
    await pumpBoard(tester, repository: sampleBoard());
    // The header slot is gone (shortcuts stay reachable via `?`, the More
    // menu and Settings → About).
    expect(find.byKey(const Key('open-keyboard-shortcuts')), findsNothing);
    await tester.tap(find.byKey(const Key('board-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-shortcuts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keyboard-shortcuts-dialog')), findsOneWidget);
  });

  testWidgets('Paste stays disabled until something is copied', (tester) async {
    final vm = await pumpBoard(tester, repository: sampleBoard());
    Future<bool> pasteEnabled() async {
      await tester.tap(find.byKey(const Key('board-more')));
      await tester.pumpAndSettle();
      final item = tester.widget<PopupMenuItem<String>>(
        find.byKey(const Key('menu-paste')),
      );
      await tester.tapAt(const Offset(700, 700));
      await tester.pumpAndSettle();
      return item.enabled;
    }

    expect(await pasteEnabled(), isFalse);
    vm.select(vm.canvasNodes.first.id);
    vm.copySelection();
    await tester.pumpAndSettle();
    expect(await pasteEnabled(), isTrue);
  });

  testWidgets('the export dialog offers every format', (tester) async {
    await pumpBoard(tester, repository: sampleBoard());
    await tester.tap(find.byTooltip('Export project'));
    await tester.pumpAndSettle();
    for (final key in const [
      'confirm-export-diagram',
      'export-png',
      'export-mermaid',
      'export-markdown',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('About reports the version and the missing WebMCP bridge', (
    tester,
  ) async {
    final settings = SettingsViewModel(
      repository: SettingsRepository(store: MemoryProjectStore()),
    );
    addTearDown(() {
      settings.dispose();
      settings.repository.dispose();
    });
    await pumpBoard(tester, settings: settings);
    await tester.tap(find.byKey(const Key('open-settings')));
    await tester.pumpAndSettle();

    expect(find.text('About'), findsOneWidget);
    expect(find.text(AppInfo.appVersion), findsOneWidget);
    expect(find.text('Agent connection'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(
      find.text('No WebMCP client detected. Foldboard works without one.'),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('technical-details')));
    await tester.pumpAndSettle();
    expect(
      find.text('No WebMCP client detected. Foldboard works without one.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('technical-details')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('open-shortcuts')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-shortcuts')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('keyboard-shortcuts-dialog')), findsOneWidget);
  });
}
