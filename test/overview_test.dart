import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_board.dart';

void main() {
  testWidgets('overview shows the whole hierarchy without changing the board', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: sampleBoard());
    addTearDown(vm.dispose);
    final before = vm.prettyJson;

    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-overview')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('overview-layer')), findsOneWidget);
    expect(find.byKey(const Key('overview-map')), findsOneWidget);
    expect(find.byKey(const Key('overview-fit-all')), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const Key('overview-map')),
    );
    expect(viewer.boundaryMargin, const EdgeInsets.all(double.infinity));
    expect(viewer.panAxis, PanAxis.free);
    expect(find.text('3 blocks · 2 connections'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('overview-fold-core-domain')),
      findsNothing,
    );
    expect(vm.prettyJson, before);
  });

  testWidgets('overview closes with Escape and preserves the current level', (
    tester,
  ) async {
    final vm = PlannerViewModel(repository: sampleBoard());
    addTearDown(vm.dispose);
    vm.openLevel('commerce-platform');

    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-overview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-open-root')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('overview-layer')), findsNothing);
    expect(vm.currentLevelId, 'commerce-platform');
  });

  testWidgets('overview has an empty state and fits a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: ArchitectureRepository());
    addTearDown(vm.dispose);

    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-overview')));
    await tester.pumpAndSettle();

    expect(find.text('Nothing to map yet'), findsOneWidget);
    expect(find.text('View only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
