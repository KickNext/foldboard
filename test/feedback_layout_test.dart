import 'package:foldboard/data/repositories/settings_repository.dart';
import 'package:foldboard/domain/models/app_settings.dart';
import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:foldboard/ui/features/settings/view_models/settings_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/project_stores.dart';
import 'support/sample_board.dart';

void main() {
  for (final width in [400.0, 1200.0]) {
    Future<void> size(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }

    testWidgets(
      'settings failures, recovery and help never move controls at $width',
      (tester) async {
        await size(tester);
        final store = MemoryProjectStore();
        final settings = SettingsViewModel(
          repository: SettingsRepository(store: store),
        );
        final planner = PlannerViewModel(
          repository: sampleBoard(),
          registerBridge: false,
        );
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
        final picker = find.byKey(const Key('appearance-picker'));
        final grid = find.byKey(const Key('show-grid'));
        final pickerRect = tester.getRect(picker);
        final gridRect = tester.getRect(grid);
        void stable() {
          expect(tester.getRect(picker), pickerRect);
          expect(tester.getRect(grid), gridRect);
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byKey(const Key('settings-info')));
        await tester.pumpAndSettle();
        stable();
        Tooltip.dismissAllToolTips();
        store.failWrite = true;
        for (var i = 0; i < 2; i++) {
          settings.setAppearance(Appearance.light);
          await tester.pumpAndSettle();
          final notice = tester.getRect(find.byKey(const Key('feedback')));
          expect(notice.overlaps(pickerRect), isFalse);
          expect(notice.overlaps(gridRect), isFalse);
          stable();
          await tester.pump(const Duration(seconds: 4));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('feedback')), findsNothing);
          stable();
        }
        store.failWrite = false;
        settings.setShowGrid(false);
        await tester.pumpAndSettle();
        expect(settings.failure, isNull);
        stable();
      },
    );

    testWidgets('catalog errors do not shift project list at $width', (
      tester,
    ) async {
      await size(tester);
      final stores = ProjectStores();
      final projects = ProjectsViewModel(repository: stores.repository());
      addTearDown(() {
        projects.dispose();
        projects.repository.dispose();
      });
      await tester.pumpWidget(FoldboardApp(projects: projects));
      await tester.pumpAndSettle();
      final tile = find.byKey(const Key('project-${Project.defaultId}'));
      final before = tester.getRect(tile);
      stores.catalog.failWrite = true;
      projects.rename(Project.defaultId, 'Will not save');
      await tester.pumpAndSettle();
      expect(tester.getRect(tile), before);
      final notice = tester.getRect(find.byKey(const Key('feedback')));
      expect(notice.overlaps(before), isFalse);
      expect(
        notice.overlaps(tester.getRect(find.byKey(const Key('new-project')))),
        isFalse,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(tester.getRect(tile), before);
      stores.catalog.failWrite = false;
      projects.rename(Project.defaultId, 'My project');
      await tester.pumpAndSettle();
      expect(tester.getRect(tile), before);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'read-only warning preserves viewport, cards and header at $width',
      (tester) async {
        await size(tester);
        final planner = PlannerViewModel(
          repository: sampleBoard(),
          registerBridge: false,
        );
        addTearDown(() {
          planner.dispose();
          planner.repository.dispose();
        });
        await tester.pumpWidget(FoldboardApp(viewModel: planner));
        await tester.pumpAndSettle();
        final canvas = find.byType(ArchitectureCanvas);
        final card = find.byKey(const Key('node-commerce-platform'));
        final canvasRect = tester.getRect(canvas);
        final cardRect = tester.getRect(card);
        final searchRect = tester.getRect(
          find.byKey(const Key('open-explorer')),
        );
        final state = tester.state(canvas);
        await tester.pumpWidget(
          FoldboardApp(viewModel: planner, writeAccess: false),
        );
        await tester.pumpAndSettle();
        expect(tester.state(canvas), same(state));
        expect(tester.getRect(canvas), canvasRect);
        expect(tester.getRect(card), cardRect);
        expect(
          tester.getRect(find.byKey(const Key('open-explorer'))),
          searchRect,
        );
        expect(find.byKey(const Key('board-feedback')), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('board-feedback')), findsNothing);
        expect(tester.getRect(card), cardRect);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
