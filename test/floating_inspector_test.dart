import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/planner/views/widgets/floating_inspector.dart';
import 'package:foldboard/ui/features/planner/views/widgets/inspector_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;

void main() {
  Future<PlannerViewModel> mount(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reduceMotion);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final vm = PlannerViewModel(
      repository: processBoard(),
      registerBridge: false,
    );
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    vm.select('human');
    await tester.pump();
    return vm;
  }

  Finder fade() => find
      .descendant(
        of: find.byType(FloatingInspector),
        matching: find.byType(FadeTransition),
      )
      .first;

  testWidgets('bubble enters and exits smoothly without resizing the board', (
    tester,
  ) async {
    await mount(tester);
    final board = tester.getRect(find.byType(ArchitectureCanvas));
    final card = tester.getRect(find.byKey(const Key('node-human')));
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade()).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.widget<FadeTransition>(fade()).opacity.value,
      allOf(greaterThan(0), lessThan(1)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FadeTransition>(fade()).opacity.value, 1);
    expect(tester.getRect(find.byType(ArchitectureCanvas)), board);
    expect(tester.getRect(find.byKey(const Key('node-human'))), card);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(InspectorPanel), findsOneWidget);
    expect(
      tester.widget<FadeTransition>(fade()).opacity.value,
      allOf(greaterThan(0), lessThan(1)),
    );
    expect(
      find.descendant(
        of: find.byType(FloatingInspector),
        matching: find.byWidgetPredicate(
          (w) => w is IgnorePointer && w.ignoring,
        ),
      ),
      findsWidgets,
    );
    await tester.pumpAndSettle();
    expect(find.byType(InspectorPanel), findsNothing);
    expect(tester.getRect(find.byType(ArchitectureCanvas)), board);
    expect(tester.getRect(find.byKey(const Key('node-human'))), card);
  });

  testWidgets(
    'replacement retains outgoing content and cannot write to the new selection',
    (tester) async {
      final vm = await mount(tester);
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      final outgoingName = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      final oldTitle = outgoingName.controller!.text;
      vm.selectGroup('app');
      await tester.pump();
      expect(find.byType(InspectorPanel), findsNWidgets(2));
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((w) => w.controller!.text),
        containsAll(['Human', 'App']),
      );
      outgoingName.onChanged!('Wrong target');
      expect(vm.selectedGroup!.title, 'App');
      expect(vm.nodes.firstWhere((n) => n.id == 'human').title, oldTitle);
      await tester.pump(const Duration(milliseconds: 70));
      vm.select('human');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Human',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion opens and closes immediately', (tester) async {
    await mount(tester, reduceMotion: true);
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pump();
    expect(tester.widget<FadeTransition>(fade()).opacity.value, 1);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pump();
    expect(find.byType(InspectorPanel), findsNothing);
  });

  testWidgets(
    'opaque reveal covers the old sheet without moving forms or queuing stale cards',
    (tester) async {
      final vm = await mount(tester);
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      final shell = tester.getRect(find.byKey(const Key('details-surface')));
      final form = tester.getRect(find.byType(InspectorPanel));
      Path clip() => tester
          .widget<ClipPath>(find.byKey(const Key('inspector-reveal')))
          .clipper!
          .getClip(form.size);
      void checkFrame() {
        expect(
          find.byType(InspectorPanel).evaluate().length,
          lessThanOrEqualTo(2),
        );
        expect(tester.getRect(find.byKey(const Key('details-surface'))), shell);
        for (final element in find.byType(InspectorPanel).evaluate()) {
          expect(tester.getRect(find.byWidget(element.widget)), form);
        }
      }

      vm.selectGroup('app');
      await tester.pump();
      expect(clip().getBounds(), Rect.zero);
      await tester.pump(const Duration(milliseconds: 80));
      final edgeBefore = clip().getBounds().left;
      expect(edgeBefore, allOf(greaterThan(0), lessThan(form.width)));
      checkFrame();
      await tester.pump(const Duration(milliseconds: 80));
      expect(clip().getBounds().left, lessThan(edgeBefore));
      // Incoming backgrounds are fully opaque: no text from the lower layer
      // can show through the revealed part of the new sheet.
      final sheet =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byKey(const Key('inspector-current-layer')),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(sheet.gradient!.colors.every((c) => c.a == 1), isTrue);
      checkFrame();
      // Rapid clicks collapse into the latest request, retaining at most two sheets.
      for (var i = 0; i < 8; i++) {
        i.isEven ? vm.select('human') : vm.selectGroup('app');
        await tester.pump();
        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          checkFrame();
        }
      }
      await tester.pumpAndSettle();
      expect(clip().getBounds(), Offset.zero & form.size);
      expect(find.byType(InspectorPanel), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'App',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
