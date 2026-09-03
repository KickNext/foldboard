import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/view_models/edge_routes.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit arrow selection has a strong visual hierarchy', () {
    expect(
      AppTheme.arrowSelectedStroke,
      greaterThan(AppTheme.arrowStroke * 1.8),
    );
    expect(
      AppTheme.arrowSelectionCasing,
      greaterThan(AppTheme.arrowSelectedStroke + 2),
    );
    expect(AppTheme.arrowSelectionMutedAlpha, lessThanOrEqualTo(.3));
    expect(AppTheme.arrowSelectedHeadScale, greaterThanOrEqualTo(1.2));
  });

  for (final brightness in Brightness.values) {
    testWidgets('arrows highlight only the explicit selection: $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = ArchitectureRepository()
        ..replace({
          'nodes': [
            {'id': 'a', 'title': 'A', 'x': 100, 'y': 200},
            {'id': 'b', 'title': 'B', 'x': 600, 'y': 200},
            {'id': 'c', 'title': 'C', 'x': 1100, 'y': 200},
          ],
          'groups': [
            {'id': 'p', 'title': 'Process', 'x': 1600, 'y': 200},
          ],
          'edges': [
            {'id': 'ab', 'from': 'a', 'to': 'b'},
            {'id': 'bc', 'from': 'b', 'to': 'c'},
            {'id': 'cp', 'from': 'c', 'to': 'p'},
          ],
        });
      final vm = PlannerViewModel(
        repository: repository,
        registerBridge: false,
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
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
      );
      await tester.pumpAndSettle();
      final data = vm.prettyJson;
      dynamic painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .firstWhere((p) => p.runtimeType.toString() == '_ViewportPainter');
      final originalRoutes = painter().routes;
      final palette = brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light;
      void expectColors(List<Color> colors, {int? selectedIndex}) {
        final canvas = _PathColorsCanvas();
        painter().paint(canvas, const Size(1200, 700));
        final expected = <Color>[];
        for (var index = 0; index < colors.length; index++) {
          if (index != selectedIndex) {
            expected.addAll([colors[index], colors[index]]);
          }
        }
        if (selectedIndex != null) {
          expected.addAll([
            palette.background,
            palette.accent,
            palette.background,
            palette.accent,
          ]);
        }
        expect(
          canvas.colors.map((c) => c.toARGB32()).toList(),
          expected.map((c) => c.toARGB32()).toList(),
        );
        expect(identical(painter().routes, originalRoutes), isTrue);
      }

      expectColors([palette.edgeMuted, palette.edgeMuted, palette.edgeMuted]);
      await tester.tap(find.byKey(const Key('node-b')));
      await tester.pumpAndSettle();
      expectColors([palette.edge, palette.edge, palette.edgeMuted]);
      vm.selectEdge('bc');
      await tester.pumpAndSettle();
      final dimmed = palette.edgeMuted.withValues(
        alpha: AppTheme.arrowSelectionMutedAlpha,
      );
      expectColors([dimmed, palette.accent, dimmed], selectedIndex: 1);
      await tester.tapAt(const Offset(1100, 600));
      await tester.pumpAndSettle();
      expect(vm.selectedEdgeId, isNull);
      expectColors([palette.edgeMuted, palette.edgeMuted, palette.edgeMuted]);
      await tester.tap(find.byKey(const Key('node-p')));
      await tester.pumpAndSettle();
      expectColors([palette.edgeMuted, palette.edgeMuted, palette.edge]);
      await tester.tapAt(const Offset(1100, 600));
      await tester.pumpAndSettle();
      expectColors([palette.edgeMuted, palette.edgeMuted, palette.edgeMuted]);
      expect(vm.prettyJson, data);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'Fit includes feedback and the painted return arrow is clickable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = ArchitectureRepository()..clear();
      for (final entry in [('a', 200.0), ('b', 900.0)]) {
        repository.addNode(
          ArchitectureNode(
            id: entry.$1,
            title: entry.$1,
            position: Offset(entry.$2, 200),
          ),
        );
      }
      repository.addEdge(
        const ArchitectureEdge(id: 'forward', from: 'a', to: 'b'),
      );
      repository.addEdge(
        const ArchitectureEdge(id: 'return', from: 'b', to: 'a'),
      );
      final vm = PlannerViewModel(
        repository: repository,
        registerBridge: false,
      );
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: defaultAppLocale,
          home: Scaffold(
            body: ListenableBuilder(
              listenable: vm,
              builder: (_, _) =>
                  ArchitectureCanvas(viewModel: vm, fitOnStart: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final snapshot = vm.prettyJson;
      dynamic painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .firstWhere((p) => p.runtimeType.toString() == '_ViewportPainter');
      final drawn = painter();
      final routes = drawn.routes as List<EdgeRoute>;
      for (final route in routes) {
        for (final point in route.points) {
          expect(
            const Rect.fromLTWH(
              40,
              40,
              1120,
              620,
            ).contains(drawn.camera.worldToScreen(point) as Offset),
            isTrue,
          );
        }
      }
      final back = routes.firstWhere((r) => r.edge.id == 'return');
      final click = drawn.camera.worldToScreen(
        Offset(back.bounds.center.dx, back.bounds.bottom),
      ) as Offset;
      await tester.tapAt(click);
      await tester.pumpAndSettle();
      expect(vm.selectedEdgeId, 'return');
      expect(vm.prettyJson, snapshot);
      // Selection changes only paint, without recalculating the geometry.
      expect(identical(painter().routes, routes), isTrue);
      final forward = routes.firstWhere((r) => r.edge.id == 'forward');
      await tester.tapAt(
        drawn.camera.worldToScreen(forward.bounds.center) as Offset,
      );
      await tester.pumpAndSettle();
      expect(vm.selectedEdgeId, 'forward');
      expect(vm.prettyJson, snapshot);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('plain arrow stays selectable without labels or popovers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = ArchitectureRepository()..clear();
    repository.addGroup(
      const ArchitectureGroup(
        id: 'area',
        title: 'Area',
        position: Offset(100, 100),
        size: Size(1200, 500),
      ),
    );
    for (final entry in [('a', 200.0), ('b', 900.0)]) {
      repository.addNode(
        ArchitectureNode(
          id: entry.$1,
          title: entry.$1,
          position: Offset(entry.$2, 200),
          parentId: 'area',
        ),
      );
    }
    repository.addEdge(const ArchitectureEdge(id: 'link', from: 'a', to: 'b'));
    final vm = PlannerViewModel(repository: repository);
    vm.openLevel('area');
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: defaultAppLocale,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => ArchitectureCanvas(viewModel: vm),
          ),
        ),
      ),
    );
    final snapshot = vm.prettyJson;
    expect(find.byKey(const ValueKey('edge-label-link')), findsNothing);
    expect(find.text('Read record'), findsNothing);
    // Selecting the line changes only its highlight, not the document.
    await tester.pumpAndSettle();
    final fromRect = tester.getRect(find.byKey(const ValueKey('node-a')));
    final toRect = tester.getRect(find.byKey(const ValueKey('node-b')));
    await tester.tapAt(
      Offset((fromRect.right + toRect.left) / 2, fromRect.center.dy),
    );
    await tester.pumpAndSettle();
    expect(vm.selectedEdgeId, 'link');
    expect(find.byKey(const Key('interaction-preview')), findsNothing);
    expect(find.text('Read record'), findsNothing);
    expect(vm.prettyJson, snapshot);
    await tester.tapAt(const Offset(650, 400));
    await tester.pumpAndSettle();
    expect(vm.selectedEdgeId, isNull);
    expect(find.byKey(const Key('interaction-preview')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Records actual path colors; unrelated canvas transforms need no rasterizer.
class _PathColorsCanvas implements Canvas {
  final colors = <Color>[];
  @override
  void drawPath(Path path, Paint paint) => colors.add(paint.color);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
