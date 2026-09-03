import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/view_models/level_graph.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/planner_page.dart';
import 'package:foldboard/ui/features/planner/views/widgets/reference_portal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'level_portal_position_test.dart' show pan;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('reference portal follows real flow and theme: $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = processBoard();
      final vm = PlannerViewModel(repository: repo, registerBridge: false);
      addTearDown(vm.dispose);
      vm.openLevel('app');
      final data = vm.prettyJson;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlannerPage(viewModel: vm),
        ),
      );
      await tester.pumpAndSettle();
      final portal = find.byKey(const Key('reference-portal-human'));
      expect(portal, findsOneWidget);
      expect(find.byKey(const Key('reference-portal-ui')), findsNothing);
      expect(find.byKey(const Key('reference-portal-inner')), findsNothing);
      expect(find.text('Input · Outside'), findsOneWidget);
      expect(vm.levelGraph.referenceFlows['human'], ReferenceFlow.input);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: portal,
                      matching: find.byWidgetPredicate(
                        (w) =>
                            w is CustomPaint &&
                            w.painter is ReferencePortalPainter,
                      ),
                    ),
                  )
                  .painter!
              as ReferencePortalPainter;
      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;
      expect(painter.palette, palette);
      expect(vm.prettyJson, data);

      repo.addEdge(
        const ArchitectureEdge(id: 'return', from: 'ui', to: 'human'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Input / Output · Outside'), findsOneWidget);
      expect(vm.levelGraph.referenceFlows['human'], ReferenceFlow.both);
      repo.applyChanges({
        'deleteIds': ['human-ui', 'human-api'],
      });
      await tester.pumpAndSettle();
      expect(find.text('Output · Outside'), findsOneWidget);
      expect(vm.levelGraph.referenceFlows['human'], ReferenceFlow.output);
      await pan(tester, const Offset(-400, 0));
      final beforeExit = vm.prettyJson;
      await tester.tap(find.byKey(const Key('enter-human')));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, isNull);
      expect(vm.selectedId, 'human');
      expect(find.byKey(const Key('reference-portal-human')), findsNothing);
      expect(vm.prettyJson, beforeExit);
      expect(tester.takeException(), isNull);
    });
  }
}
