import 'dart:convert';

import 'package:foldboard/data/repositories/settings_repository.dart';
import 'package:foldboard/domain/models/app_settings.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/core/segmented_picker.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:foldboard/ui/features/settings/view_models/settings_view_model.dart';
import 'package:foldboard/ui/features/settings/views/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/project_stores.dart';
import 'support/sample_board.dart';

void main() {
  test('defaults and saved settings round-trip independently of boards', () {
    final store = MemoryProjectStore();
    final repo = SettingsRepository(store: store);
    expect(repo.value.appearance, Appearance.dark);
    expect(repo.value.showGrid, isTrue);
    expect(repo.value.agentReadOnly, isFalse);
    expect(
      repo.save(
        const AppSettings(appearance: Appearance.system, showGrid: false),
      ),
      isTrue,
    );
    final restored = SettingsRepository(store: store);
    expect(restored.value.appearance, Appearance.system);
    expect(restored.value.showGrid, isFalse);
    expect(
      jsonDecode(store.value!).keys,
      unorderedEquals(['appearance', 'showGrid', 'agentReadOnly']),
    );
    restored.dispose();
    repo.dispose();
  });

  testWidgets('agent access is explicit and starts in edit mode', (
    tester,
  ) async {
    final store = MemoryProjectStore();
    final settings = SettingsViewModel(
      repository: SettingsRepository(store: store),
    );
    addTearDown(() {
      settings.dispose();
      settings.repository.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsPage(viewModel: settings),
      ),
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<SegmentedButton<bool>>(
      find.byKey(const Key('agent-access')),
    );
    expect(picker.selected, {false});
    expect(find.text('View only'), findsOneWidget);
    expect(find.text('View and edit'), findsOneWidget);

    await tester.tap(find.text('View only'));
    await tester.pumpAndSettle();
    expect(settings.value.agentReadOnly, isTrue);
    expect(
      tester
          .widget<SegmentedButton<bool>>(find.byKey(const Key('agent-access')))
          .selected,
      {true},
    );
    final restored = SettingsRepository(store: store);
    expect(restored.value.agentReadOnly, isTrue);
    restored.dispose();
  });

  test('failed saves do not apply unsaved preferences and can be retried', () {
    final store = MemoryProjectStore()..failWrite = true;
    final repo = SettingsRepository(store: store);
    expect(repo.save(const AppSettings(appearance: Appearance.light)), isFalse);
    expect(repo.value.appearance, Appearance.dark);
    expect(repo.failure, SettingsFailure.write);
    store.failWrite = false;
    expect(repo.save(const AppSettings(appearance: Appearance.light)), isTrue);
    expect(repo.failure, isNull);
    repo.dispose();
  });

  test(
    'corrupt and unsupported settings are preserved until explicit reset',
    () {
      for (final raw in [
        '{bad',
        '{"appearance":"dark"}',
        '{"appearance":"unknown","showGrid":true,"agentReadOnly":false}',
        '{"appearance":"dark","showGrid":true}',
      ]) {
        final store = MemoryProjectStore()..value = raw;
        final repo = SettingsRepository(store: store);
        expect(repo.failure, SettingsFailure.read);
        expect(repo.canEdit, isFalse);
        expect(repo.save(const AppSettings()), isFalse);
        expect(store.value, raw);
        expect(repo.save(const AppSettings(), reset: true), isTrue);
        expect(repo.canEdit, isTrue);
        repo.dispose();
      }
    },
  );

  test('both palettes retain readable text and theme-owned colors', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final theme in [AppTheme.dark, AppTheme.light]) {
      final p = theme.extension<AppPalette>()!;
      expect(theme.scaffoldBackgroundColor, p.background);
      expect(theme.colorScheme.primary, p.accent);
      expect(contrast(p.text, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.muted, p.surface), greaterThanOrEqualTo(4.5));
    }
  });

  for (final width in [400.0, 1200.0]) {
    testWidgets(
      'settings update theme and grid without losing board state at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryProjectStore();
        final settings = SettingsViewModel(
          repository: SettingsRepository(store: store),
        );
        final planner = PlannerViewModel(repository: sampleBoard());
        addTearDown(() {
          settings.dispose();
          settings.repository.dispose();
          planner.dispose();
          planner.repository.dispose();
        });
        await tester.pumpWidget(
          FoldboardApp(viewModel: planner, settings: settings),
        );
        planner.select('web-client');
        await tester.pumpAndSettle();
        final before = planner.prettyJson;
        final canvasState = tester.state(find.byType(ArchitectureCanvas));
        final cardPosition = tester.getRect(
          find.byKey(const ValueKey('node-web-client')),
        );
        await tester.tap(find.byKey(const Key('open-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('appearance-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Light').last);
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(SettingsPage))).brightness,
          Brightness.light,
        );
        await tester.tap(find.byKey(const Key('show-grid')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<ArchitectureCanvas>(find.byType(ArchitectureCanvas))
              .showGrid,
          isFalse,
        );
        expect(
          tester.state(find.byType(ArchitectureCanvas)),
          same(canvasState),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('node-web-client'))),
          cardPosition,
        );
        expect(planner.prettyJson, before);
        expect(planner.selectedId, 'web-client');
        final restored = SettingsRepository(store: store);
        expect(restored.value.appearance, Appearance.light);
        expect(restored.value.showGrid, isFalse);
        restored.dispose();
        await tester.tap(find.byKey(const Key('open-settings')));
        await tester.pumpAndSettle();
        // Reset lives in the danger zone at the end of the page.
        await tester.scrollUntilVisible(
          find.byKey(const Key('reset-settings')),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reset-settings')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
        await tester.pumpAndSettle();
        expect(settings.value.appearance, Appearance.dark);
        expect(settings.showGrid, isTrue);
        expect(planner.prettyJson, before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'system mode responds to device appearance and projects expose settings',
    (tester) async {
      final stores = ProjectStores();
      final projects = ProjectsViewModel(repository: stores.repository());
      final settings = SettingsViewModel(
        repository: SettingsRepository(store: MemoryProjectStore()),
      );
      addTearDown(() {
        projects.dispose();
        projects.repository.dispose();
        settings.dispose();
        settings.repository.dispose();
      });
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.light;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      settings.setAppearance(Appearance.system);
      await tester.pumpWidget(
        FoldboardApp(projects: projects, settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.light,
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark,
      );
      expect(projects.planner, isNull);
    },
  );

  testWidgets(
    'repeated storage errors leave the theme picker on the saved value',
    (tester) async {
      final store = MemoryProjectStore()..failWrite = true;
      final settings = SettingsViewModel(
        repository: SettingsRepository(store: store),
      );
      final planner = PlannerViewModel(repository: sampleBoard());
      addTearDown(() {
        settings.dispose();
        settings.repository.dispose();
        planner.dispose();
        planner.repository.dispose();
      });
      await tester.pumpWidget(
        FoldboardApp(viewModel: planner, settings: settings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-settings')));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byKey(const Key('appearance-picker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Light').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SegmentedPicker<Appearance>>(
                find.byKey(const Key('appearance-picker')),
              )
              .value,
          Appearance.dark,
        );
        expect(settings.failure, SettingsFailure.write);
      }
    },
  );
}
