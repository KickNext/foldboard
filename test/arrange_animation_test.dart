import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<PlannerViewModel> mount(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    final repo = ArchitectureRepository()..clear();
    repo.applyChanges({
      'nodes': [
        const ArchitectureNode(
          id: 'a',
          title: 'First',
          position: Offset(400, 250),
        ).toJson(),
        const ArchitectureNode(
          id: 'b',
          title: 'Second',
          position: Offset(650, 280),
        ).toJson(),
      ],
      'edges': [const ArchitectureEdge(id: 'ab', from: 'a', to: 'b').toJson()],
    });
    final vm = PlannerViewModel(repository: repo, registerBridge: false);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: defaultAppLocale,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (_, _) => ArchitectureCanvas(viewModel: vm),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  Rect card(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('node-a')));

  testWidgets(
    'Arrange interpolates cards, arrows and camera without extra writes',
    (tester) async {
      final vm = await mount(tester);
      final before = card(tester);
      // The Arrange button lives on PlannerPage's level path row; this test
      // mounts the canvas alone, so trigger the same command directly.
      vm.arrangeCurrent();
      await tester.pump();
      final saved = vm.prettyJson;
      expect(card(tester), before);
      await tester.pump(const Duration(milliseconds: 180));
      final middle = card(tester);
      expect(middle, isNot(before));
      // The edge painter uses the same interpolated coordinates as the cards.
      final dynamic painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .firstWhere((p) => p.runtimeType.toString() == '_ViewportPainter');
      final node = (painter.nodes as List<ArchitectureNode>).firstWhere(
        (n) => n.id == 'a',
      );
      expect(painter.camera.worldToScreen(node.position), middle.topLeft);
      expect(node.position, isNot(vm.nodes.first.position));
      await tester.pumpAndSettle();
      expect(card(tester), isNot(middle));
      expect(vm.prettyJson, saved);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('WebMCP Arrange retargets from the visible frame', (
    tester,
  ) async {
    final vm = await mount(tester);
    vm.autoArrange();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final before = card(tester);
    vm.autoArrange();
    await tester.pump();
    expect(card(tester), before);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion applies Arrange immediately', (tester) async {
    final vm = await mount(tester, reduceMotion: true);
    final before = card(tester);
    vm.autoArrange();
    await tester.pump();
    expect(card(tester), isNot(before));
    // The closing fit lands one frame later; from then on everything rests.
    await tester.pumpAndSettle();
    final rest = card(tester);
    await tester.pump(const Duration(milliseconds: 180));
    expect(card(tester), rest);
  });

  testWidgets(
    'Tidy may snap a selected outlier and ends framed; repeat is a no-op',
    (tester) async {
      final vm = await mount(tester);
      vm.selectCard('a');
      await tester.pumpAndSettle();
      final before = card(tester);
      vm.autoArrange();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(card(tester), isNot(before));
      await tester.pumpAndSettle();
      expect(card(tester), isNot(before));
      // Arrange ends framed: every card sits inside the visible rect, so a
      // small tidy-up never looks like a dead button.
      final after = vm.readViewport!();
      final visible = Rect.fromLTWH(
        (after['x'] as num).toDouble(),
        (after['y'] as num).toDouble(),
        (after['width'] as num).toDouble(),
        (after['height'] as num).toDouble(),
      );
      for (final node in vm.nodes) {
        expect(visible.contains(node.position), isTrue);
      }
      final revision = vm.repository.revision;
      final animation = vm.arrangeVersion;
      vm.autoArrange();
      await tester.pumpAndSettle();
      expect(vm.repository.revision, revision);
      expect(vm.arrangeVersion, animation);
    },
  );

  testWidgets(
    'dragging during Arrange follows the pointer without delayed movement',
    (tester) async {
      final vm = await mount(tester);
      vm.autoArrange();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final start = card(tester);
      final gesture = await tester.startGesture(start.center);
      await tester.pump();
      expect(card(tester), start);
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      final before = card(tester);
      await gesture.moveBy(const Offset(60, 20));
      await tester.pump();
      expect(
        ((card(tester).topLeft - before.topLeft) - const Offset(60, 20))
            .distance,
        lessThan(.000001),
      );
      await gesture.up();
      final end = card(tester);
      await tester.pumpAndSettle();
      expect(card(tester), end);
      expect(tester.takeException(), isNull);
    },
  );
}
