import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/view_models/edge_routes.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

dynamic painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .firstWhere((p) => p.runtimeType.toString() == '_ViewportPainter');

Future<PlannerViewModel> mount(
  WidgetTester tester, {
  bool reduced = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = ArchitectureRepository()
    ..replace({
      'nodes': [
        {'id': 'a', 'title': 'A', 'x': 200, 'y': 200},
        {'id': 'b', 'title': 'B', 'x': 900, 'y': 200},
        {'id': 'c', 'title': 'C', 'x': 1600, 'y': 200},
      ],
      'groups': [],
      'edges': [
        {'id': 'ab', 'from': 'a', 'to': 'b'},
        {'id': 'ba', 'from': 'b', 'to': 'a'},
        {'id': 'bc', 'from': 'b', 'to': 'c'},
      ],
    });
  final vm = PlannerViewModel(repository: repo, registerBridge: false);
  addTearDown(vm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (_, _) => ArchitectureCanvas(
              viewModel: vm,
              fitOnStart: true,
              showGrid: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

class _Paths implements Canvas {
  final paths = <(Path, Color, PaintingStyle)>[];
  @override
  void drawPath(Path path, Paint paint) =>
      paths.add((path, paint.color, paint.style));
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets(
    'ignition follows forward and curved return paths without rebuilding cards',
    (tester) async {
      final vm = await mount(tester);
      final data = vm.prettyJson;
      final routes = painter(tester).routes as List<EdgeRoute>;
      vm.select('a');
      await tester.pump();
      expect(painter(tester).ignitionProgress, 0);
      final card = tester.widget(find.byKey(const Key('node-b')));
      await tester.pump(AppTheme.edgeIgnition ~/ 2);
      final drawn = painter(tester);
      final progress = drawn.ignitionProgress as double;
      expect(progress, inExclusiveRange(.4, .6));
      expect(identical(drawn.routes, routes), isTrue);
      expect(
        identical(tester.widget(find.byKey(const Key('node-b'))), card),
        isTrue,
      );
      final canvas = _Paths();
      drawn.paint(canvas, const Size(1200, 700));
      final palette = drawn.palette as AppPalette;
      final lit = canvas.paths
          .where(
            (p) =>
                p.$3 == PaintingStyle.stroke &&
                p.$2.toARGB32() == palette.edge.toARGB32(),
          )
          .toList();
      expect(lit, hasLength(2));
      for (var i = 0; i < lit.length; i++) {
        final original = routes[i].metric!;
        final prefix = lit[i].$1.computeMetrics().single;
        expect(prefix.length, closeTo(original.length * progress, .2));
        expect(
          prefix.getTangentForOffset(0)!.position,
          offsetMoreOrLessEquals(original.getTangentForOffset(0)!.position),
        );
        expect(
          prefix.getTangentForOffset(prefix.length)!.position,
          offsetMoreOrLessEquals(
            original.getTangentForOffset(original.length * progress)!.position,
            epsilon: .2,
          ),
        );
      }
      // All heads are still unlit until the wave arrives; unrelated BC stays dim.
      expect(
        canvas.paths
            .where((p) => p.$3 == PaintingStyle.fill)
            .map((p) => p.$2.toARGB32()),
        everyElement(palette.edgeMuted.toARGB32()),
      );
      await tester.pumpAndSettle();
      expect(painter(tester).ignitionProgress, 1);
      final settled = _Paths();
      painter(tester).paint(settled, const Size(1200, 700));
      expect(settled.paths.map((p) => p.$2.toARGB32()).toList(), [
        palette.edge.toARGB32(),
        palette.edge.toARGB32(),
        palette.edge.toARGB32(),
        palette.edge.toARGB32(),
        palette.edgeMuted.toARGB32(),
        palette.edgeMuted.toARGB32(),
      ]);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(vm.prettyJson, data);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing selection restarts only the new wave; clear and edge selection stop it',
    (tester) async {
      final vm = await mount(tester);
      vm.select('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(painter(tester).ignitionProgress, greaterThan(0));
      vm.select('c');
      await tester.pump();
      expect(painter(tester).selectedNodeId, 'c');
      expect(painter(tester).ignitionProgress, 0);
      await tester.pump(const Duration(milliseconds: 100));
      vm.selectEdge('ba');
      await tester.pumpAndSettle();
      expect(painter(tester).selectedEdgeId, 'ba');
      expect(painter(tester).ignitionProgress, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      vm.select('a');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      vm.select(null);
      await tester.pumpAndSettle();
      expect(painter(tester).selectedNodeId, isNull);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion highlights immediately without a wave', (
    tester,
  ) async {
    final vm = await mount(tester, reduced: true);
    vm.select('a');
    await tester.pump();
    expect(painter(tester).ignitionProgress, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
