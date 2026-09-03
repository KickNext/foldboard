import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/project_stores.dart';

void main() {
  for (final width in [400.0, 1200.0]) {
    testWidgets('create, name, switch and reload projects at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stores = ProjectStores();
      var vm = ProjectsViewModel(repository: stores.repository());
      addTearDown(() {
        vm.dispose();
        vm.repository.dispose();
      });
      await tester.pumpWidget(FoldboardApp(projects: vm));
      await tester.pumpAndSettle();
      expect(find.text('Projects'), findsOneWidget);
      expect(find.byKey(const Key('getting-started')), findsOneWidget);
      expect(find.text('Start with one flow'), findsOneWidget);
      expect(find.byKey(const Key('open-starter-board')), findsOneWidget);
      expect(find.byKey(const Key('explore-example')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('rename-project-${Project.defaultId}')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('project-name')),
        'First project',
      );
      await tester.tap(find.byKey(const Key('save-project-name')));
      await tester.pumpAndSettle();
      expect(find.text('First project'), findsOneWidget);
      await tester.tap(find.byKey(const Key('project-${Project.defaultId}')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('open-explorer'))).left,
        greaterThan(tester.getRect(find.text('First project')).right),
      );
      vm.planner!.addNode(title: 'Keep me');
      await tester.pumpAndSettle();
      final backPosition = tester.getTopLeft(
        find.byKey(const Key('back-to-projects')),
      );
      final process = vm.planner!.addGroup();
      vm.planner!.openLevel(process.id);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const Key('level-up'))),
        backPosition,
      );
      expect(find.byKey(const Key('back-to-projects')), findsNothing);
      await tester.tap(find.byKey(const Key('level-up')));
      await tester.pumpAndSettle();
      expect(vm.planner!.currentLevelId, isNull);
      expect(
        tester.getTopLeft(find.byKey(const Key('back-to-projects'))),
        backPosition,
      );
      await tester.tap(find.byKey(const Key('back-to-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-project')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-project-name')))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('project-name')),
        'Second project',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-project-name')));
      await tester.pumpAndSettle();
      expect(find.text('Second project'), findsOneWidget);
      expect(vm.planner!.nodes, isEmpty);
      vm.planner!.addNode(title: 'Second only');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back-to-projects')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-${Project.defaultId}')));
      await tester.pumpAndSettle();
      expect(vm.planner!.nodes.single.title, 'Keep me');
      // Recreate the entire app and repositories using the same persistent store.
      await tester.pumpWidget(const SizedBox());
      vm.dispose();
      vm.repository.dispose();
      vm = ProjectsViewModel(repository: stores.repository());
      await tester.pumpWidget(FoldboardApp(projects: vm));
      await tester.pumpAndSettle();
      expect(find.text('First project'), findsOneWidget);
      expect(vm.planner!.nodes.single.title, 'Keep me');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Explore example creates and opens an editable local copy', (
    tester,
  ) async {
    final stores = ProjectStores();
    final vm = ProjectsViewModel(repository: stores.repository());
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });

    await tester.pumpWidget(FoldboardApp(projects: vm));
    await tester.pumpAndSettle();
    expect(
      find.text('See a person and agent work across bounded levels.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('explore-example')));
    await tester.pumpAndSettle();

    expect(vm.activeProject!.name, 'Example project');
    expect(vm.planner!.nodes.map((node) => node.title), contains('Agent plan'));
    expect(find.text('Example project'), findsOneWidget);
    expect(find.byKey(const Key('back-to-projects')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
