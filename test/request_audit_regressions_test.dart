import 'dart:convert';

import 'package:foldboard/data/repositories/board_requests_repository.dart';
import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  testWidgets(
    'project exit protects drafts, including agent project switches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final projects = ProjectsViewModel(
        repository: ProjectStores().repository(),
      );
      addTearDown(() {
        projects.dispose();
        projects.repository.dispose();
      });
      projects.open(Project.defaultId);
      await tester.pumpWidget(FoldboardApp(projects: projects));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-agent-requests')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-request')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('request-text')),
        'Keep my draft',
      );
      final before = projects.planner;
      final count = projects.projects.length;
      final result = jsonDecode(
        projects.handleToolCall(
          jsonEncode({
            'tool': 'create-project',
            'args': {'name': 'Must not create'},
          }),
        ),
      ) as Map;
      expect(result['code'], 'unsaved-draft');
      expect(projects.projects.length, count);
      expect(projects.planner, same(before));
      final other = projects.repository.create('Other');
      final switched = jsonDecode(
        projects.handleToolCall(
          jsonEncode({
            'tool': 'open-project',
            'args': {'id': other.id},
          }),
        ),
      ) as Map;
      expect(switched['code'], 'unsaved-draft');
      expect(projects.planner, same(before));

      await tester.tap(find.byKey(const Key('back-to-projects')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(projects.planner, same(before));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('request-text')))
            .controller!
            .text,
        'Keep my draft',
      );
      await tester.tap(find.byKey(const Key('back-to-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(projects.planner, isNull);
      expect(find.text('Projects'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1164, 655),
    const Size(800, 364),
    const Size(400, 640),
  ]) {
    testWidgets('requests remain usable without overlap at $size', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vm = PlannerViewModel(
        repository: processBoard(),
        requests: BoardRequestsRepository(store: MemoryProjectStore()),
        registerBridge: false,
      );
      addTearDown(() {
        vm.dispose();
        vm.repository.dispose();
      });
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      vm.selectCard('human');
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byType(ArchitectureCanvas));
      expect(find.byKey(const Key('selection-summary')), findsOneWidget);
      await tester.tap(find.byKey(const Key('comment-selection')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-summary')), findsNothing);
      expect(tester.getRect(find.byType(ArchitectureCanvas)), canvas);
      expect(tester.takeException(), isNull);
      final panel = tester.getRect(find.byKey(const Key('requests-surface')));
      final save = tester.getRect(find.byKey(const Key('save-request')));
      expect(panel.contains(save.topLeft), isTrue);
      expect(panel.contains(save.bottomRight), isTrue);
      await tester.enterText(
        find.byKey(const Key('request-text')),
        'Saved in a short window',
      );
      await tester.pumpAndSettle();
      // Footer is outside the scrollable body: no scroll is required to save.
      expect(
        find.byKey(const Key('save-request')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('save-request')));
      await tester.pumpAndSettle();
      expect(vm.requests.items.single.text, 'Saved in a short window');
      expect(
        find.byKey(const Key('new-request')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('close-agent-requests')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('selection-summary')), findsOneWidget);
      expect(tester.getRect(find.byType(ArchitectureCanvas)), canvas);
    });
  }

  testWidgets('export explains exclusions before downloading', (tester) async {
    final vm = PlannerViewModel(
      repository: processBoard(),
      registerBridge: false,
    );
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Export project'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Agent requests and replies are not included'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('confirm-export-diagram')), findsOneWidget);
    expect(find.byKey(const Key('export-markdown')), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
