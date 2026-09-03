import 'dart:convert';

import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/storage_keys.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:foldboard/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  testWidgets('opening the active project frames its whole board', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1536, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final stores = ProjectStores();
    stores.catalog.value = jsonEncode({
      'projects': [
        {'id': Project.defaultId, 'name': 'Billing migration'},
      ],
      'activeId': Project.defaultId,
    });
    stores
        .board(StorageKeys.projectBoard(Project.defaultId))
        .value = jsonEncode({
      'revision': 1,
      'groups': [
        {
          'id': 'mig',
          'title': 'Migration',
          'x': 760,
          'y': 260,
          'width': 760,
          'height': 480,
          'parentId': null,
        },
      ],
      'nodes': [
        {'id': 'kickoff', 'title': 'Kickoff', 'x': 200, 'y': 260},
        {'id': 'audit', 'title': 'Audit', 'x': 480, 'y': 260},
        {'id': 'cutover', 'title': 'Cutover', 'x': 1040, 'y': 260},
      ],
      'edges': [
        {'id': 'e1', 'from': 'kickoff', 'to': 'audit'},
      ],
    });
    final projects = ProjectsViewModel(repository: stores.repository());
    addTearDown(() {
      projects.dispose();
      projects.repository.dispose();
    });
    await tester.pumpWidget(FoldboardApp(projects: projects));
    await tester.pumpAndSettle();
    final vm = projects.planner!;
    final viewport = vm.readViewport!();
    final visible = Rect.fromLTWH(
      (viewport['x'] as num).toDouble(),
      (viewport['y'] as num).toDouble(),
      (viewport['width'] as num).toDouble(),
      (viewport['height'] as num).toDouble(),
    );
    for (final node in vm.canvasNodes) {
      expect(
        visible.contains(node.position),
        isTrue,
        reason: '${node.id} at ${node.position} outside $visible',
      );
    }
  });

  testWidgets('first frame after load fits the whole board', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1536, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: processBoard());
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    final viewport = vm.readViewport!();
    final visible = Rect.fromLTWH(
      (viewport['x'] as num).toDouble(),
      (viewport['y'] as num).toDouble(),
      (viewport['width'] as num).toDouble(),
      (viewport['height'] as num).toDouble(),
    );
    for (final node in vm.canvasNodes) {
      expect(
        visible.contains(node.position),
        isTrue,
        reason: '${node.id} at ${node.position} outside $visible',
      );
    }
  });

  testWidgets('a viewport change before any interaction re-fits the board', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: processBoard());
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(1536, 750));
    await tester.pumpAndSettle();
    final viewport = vm.readViewport!();
    final visible = Rect.fromLTWH(
      (viewport['x'] as num).toDouble(),
      (viewport['y'] as num).toDouble(),
      (viewport['width'] as num).toDouble(),
      (viewport['height'] as num).toDouble(),
    );
    for (final node in vm.canvasNodes) {
      expect(
        visible.contains(node.position),
        isTrue,
        reason: '${node.id} at ${node.position} outside $visible',
      );
    }
  });
}
