import 'support/sample_board.dart';

import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [400.0, 600.0, 800.0, 1200.0]) {
    testWidgets('canvas and on-demand details work at width $width', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vm = PlannerViewModel(repository: sampleBoard());
      addTearDown(vm.dispose);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();

      expect(find.byType(InspectorPanel), findsNothing);
      expect(tester.getSize(find.byType(ArchitectureCanvas)).width, width);
      expect(find.byKey(const Key('open-explorer')), findsOneWidget);

      vm.select('core-service');
      await tester.pumpAndSettle();
      // Selecting a node does not steal canvas space.
      expect(find.byType(InspectorPanel), findsNothing);
      final beforeOpen = tester.getRect(
        find.byKey(const ValueKey('node-core-service')),
      );
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      final detailRect = tester.getRect(
        find.byKey(const Key('details-surface')),
      );
      if (width < 700) {
        expect(detailRect.width, width < 444 ? width - 24 : 420);
        // The compact sheet leaves the notification lane and zoom controls free.
        final canvas = tester.getRect(find.byType(ArchitectureCanvas));
        expect(
          detailRect.height,
          closeTo((canvas.height - 168 - 12 - 76).clamp(0, 480), .01),
        );
        expect(detailRect.top, greaterThanOrEqualTo(canvas.top + 168));
        expect(detailRect.bottom, lessThan(800));
      } else {
        expect(detailRect.width, 380);
      }
      final canvasRect = tester.getRect(find.byType(ArchitectureCanvas));
      expect(canvasRect.overlaps(detailRect), isTrue);
      expect(canvasRect.width, width);
      expect(detailRect.right, lessThan(width));
      final selectedRect = tester.getRect(
        find.byKey(const ValueKey('node-core-service')),
      );
      expect(selectedRect, beforeOpen);
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsNothing);
      expect(vm.selectedId, 'core-service');
      expect(
        tester.getRect(find.byKey(const ValueKey('node-core-service'))),
        beforeOpen,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'narrow navigation remains reachable and closes after choosing a component',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final vm = PlannerViewModel(repository: sampleBoard());
      addTearDown(vm.dispose);
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-explorer')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('board-search')),
        'Order service',
      );
      await tester.pumpAndSettle();
      final drawerNode = find.byKey(
        const ValueKey('search-result-core-service'),
      );
      await tester.tap(drawerNode);
      await tester.pumpAndSettle();
      expect(vm.selectedId, 'core-service');
      expect(find.byKey(const Key('board-search-dialog')), findsNothing);
      expect(vm.cameraTargetId, 'core-service');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open inspector adapts when chat reduces available width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = PlannerViewModel(repository: sampleBoard());
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    vm.select('core-service');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pumpAndSettle();
    final beforeResize = tester.getRect(
      find.byKey(const ValueKey('node-core-service')),
    );
    await tester.binding.setSurfaceSize(const Size(600, 800));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('details-surface'))).width, 420);
    final nodeRect = tester.getRect(
      find.byKey(const ValueKey('node-core-service')),
    );
    expect(nodeRect, beforeResize);
    expect(vm.selectedId, 'core-service');
    expect(tester.takeException(), isNull);
  });
}
