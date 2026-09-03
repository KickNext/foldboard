import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/planner_page.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/planner/views/widgets/level_portal_transition.dart';
import 'package:foldboard/ui/features/planner/views/widgets/process_portal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RRect aperture(WidgetTester tester) =>
    (tester.widget<ClipRRect>(find.byKey(const Key('portal-aperture'))).clipper!
            as PortalApertureClipper)
        .aperture;

void main() {
  Future<PlannerViewModel> mount(
    WidgetTester tester, {
    bool reduced = false,
    bool fullPage = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = ArchitectureRepository()
      ..replace({
        'groups': [
          {'id': 'app', 'title': 'App', 'x': 700, 'y': 260},
          {
            'id': 'inner',
            'title': 'Inner',
            'parentId': 'app',
            'x': 900,
            'y': 300,
          },
        ],
        'nodes': [
          {'id': 'human', 'title': 'Human', 'x': 200, 'y': 260},
          {'id': 'ui', 'title': 'UI', 'parentId': 'app', 'x': 400, 'y': 300},
        ],
        'edges': [
          {'id': 'link', 'from': 'human', 'to': 'ui'},
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
          child: fullPage
              ? PlannerPage(viewModel: vm)
              : Scaffold(
                  body: ListenableBuilder(
                    listenable: vm,
                    builder: (_, _) =>
                        ArchitectureCanvas(viewModel: vm, fitOnStart: true),
                  ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return vm;
  }

  testWidgets(
    'page keeps the canvas alive through entry, breadcrumbs and back',
    (tester) async {
      final vm = await mount(tester, fullPage: true);
      final data = vm.prettyJson;
      final canvas = tester.state(find.byType(ArchitectureCanvas));
      final card = tester.getRect(find.byKey(const Key('node-app')));
      await tester.tap(find.byKey(const Key('enter-app')));
      await tester.pump();
      final canvasTopLeft = tester.getTopLeft(find.byType(ArchitectureCanvas));
      expect(aperture(tester).outerRect.shift(canvasTopLeft), card);
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.state(find.byType(ArchitectureCanvas)), same(canvas));
      expect(find.byKey(const Key('level-root')), findsOneWidget);
      expect(find.byKey(const Key('portal-outgoing')), findsOneWidget);
      expect(aperture(tester).width, greaterThan(260));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('level-up')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(tester.state(find.byType(ArchitectureCanvas)), same(canvas));
      // The path row is permanent; at the root its crumb is just disabled.
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('level-root')))
            .onPressed,
        isNull,
      );
      expect(aperture(tester).width, lessThan(1200));
      await tester.pumpAndSettle();
      expect(vm.currentLevelId, isNull);
      expect(vm.prettyJson, data);
      expect(find.byKey(const Key('portal-outgoing')), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'full-card mirror is centered at rest and gains perspective on hover',
    () {
      for (final depth in [0.0, .5, 1.0]) {
        const size = Size(260, 118);
        final well = InfinityMirrorPainter.window(size);
        final rings = InfinityMirrorPainter.reflections(size, depth);
        expect(well.top, closeTo(AppTheme.mirrorInset, .000001));
        expect(well, const Rect.fromLTWH(12, 12, 236, 94));
        expect(well.left, closeTo(AppTheme.mirrorInset, .000001));
        expect(size.width - well.right, closeTo(AppTheme.mirrorInset, .000001));
        expect(
          size.height - well.bottom,
          closeTo(AppTheme.mirrorInset, .000001),
        );
        expect(
          rings.first.outerRect,
          rectMoreOrLessEquals(well, epsilon: .000001),
        );
        for (var i = 0; i < rings.length; i++) {
          expect(rings[i].center.dy, closeTo(well.center.dy, .000001));
          if (depth == 0 || i == 0) {
            expect(rings[i].center.dx, closeTo(well.center.dx, .000001));
          } else {
            expect(rings[i].center.dx, greaterThan(well.center.dx));
            expect(rings[i].center.dx, greaterThan(rings[i - 1].center.dx));
          }
          expect(
            well.inflate(.000001).contains(rings[i].outerRect.topLeft),
            isTrue,
          );
          expect(
            rings[i].outerRect.right,
            lessThanOrEqualTo(well.right + .000001),
          );
          if (i > 0) {
            expect(rings[i].width, lessThan(rings[i - 1].width));
            expect(rings[i].height, lessThan(rings[i - 1].height));
          }
        }
      }
    },
  );

  test(
    'first mirror is a parallel 12px inset with concentric circular corners',
    () {
      for (final size in [
        const Size(260, 118),
        const Size(118, 260),
        const Size(400, 180),
      ]) {
        for (final depth in [0.0, .5, 1.0]) {
          final rings = InfinityMirrorPainter.reflections(size, depth);
          final well = InfinityMirrorPainter.window(size);
          expect(well.left, AppTheme.mirrorInset);
          expect(well.top, AppTheme.mirrorInset);
          expect(size.width - well.right, AppTheme.mirrorInset);
          expect(size.height - well.bottom, AppTheme.mirrorInset);
          final first = rings.first;
          expect(first.tlRadius, const Radius.circular(12));
          expect(
            first.left + first.tlRadiusX,
            closeTo(AppTheme.radiusProcessCard, .000001),
          );
          expect(
            first.top + first.tlRadiusY,
            closeTo(AppTheme.radiusProcessCard, .000001),
          );
          expect(
            first.right - first.trRadiusX,
            closeTo(size.width - AppTheme.radiusProcessCard, .000001),
          );
          expect(
            first.bottom - first.brRadiusY,
            closeTo(size.height - AppTheme.radiusProcessCard, .000001),
          );
        }
      }
    },
  );

  test('hover only shifts into depth without expansion or square corners', () {
    for (final size in [
      const Size(260, 118),
      const Size(118, 260),
      const Size(400, 180),
    ]) {
      final idle = InfinityMirrorPainter.reflections(size, 0);
      for (final depth in [0.0, .1, .25, .5, .75, .9, 1.0]) {
        var parent = RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppTheme.radiusProcessCard),
        );
        final rings = InfinityMirrorPainter.reflections(size, depth);
        expect(rings, hasLength(8));
        for (var i = 0; i < rings.length; i++) {
          final ring = rings[i];
          expect(ring.width, lessThanOrEqualTo(idle[i].width + .000001));
          expect(ring.height, lessThanOrEqualTo(idle[i].height + .000001));
          expect(ring.width, greaterThan(idle[i].width * .85));
          expect(ring.center.dy, closeTo(idle[i].center.dy, .000001));
          expect(
            parent.outerRect.inflate(.000001).contains(ring.outerRect.topLeft),
            isTrue,
          );
          expect(ring.right, lessThanOrEqualTo(parent.right + .000001));
          expect(ring.bottom, lessThanOrEqualTo(parent.bottom + .000001));
          for (final radius in [
            ring.tlRadius,
            ring.trRadius,
            ring.blRadius,
            ring.brRadius,
          ]) {
            expect(radius.x, greaterThan(0));
            expect(radius.y, greaterThan(0));
          }
          if (depth > 0 && i > 0) {
            expect(ring.center.dx, greaterThan(idle[i].center.dx));
          }
          parent = ring;
        }
      }
    }
  });

  testWidgets(
    'only processes have mirrors; hover settles without idle tickers',
    (tester) async {
      final vm = await mount(tester);
      expect(find.byType(ProcessPortal), findsOneWidget);
      expect(find.byKey(const ValueKey('portal-app')), findsOneWidget);
      for (final entry in {
        'app': AppTheme.radiusProcessCard,
        'human': AppTheme.radiusCard,
      }.entries) {
        final box = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byKey(ValueKey('node-${entry.key}')),
                matching: find.byType(Container),
              ),
            )
            .map((w) => w.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.border != null);
        expect(box.borderRadius, BorderRadius.circular(entry.value));
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1100, 600));
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('node-app'))),
      );
      await tester.pumpAndSettle();
      final mirror = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<InfinityMirrorPainter>()
          .single;
      expect(mirror.depth, 1);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await mouse.removePointer();
      vm.openLevel('app');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('portal-inner')), findsOneWidget);
      expect(find.byKey(const ValueKey('portal-human')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('enter and return reverse flight and restore the parent camera', (
    tester,
  ) async {
    final vm = await mount(tester);
    final data = vm.prettyJson;
    await tester.dragFrom(const Offset(1050, 550), const Offset(-60, 30));
    await tester.pumpAndSettle();
    final before = tester.getRect(find.byKey(const ValueKey('node-app')));
    final tools = tester.getRect(find.byKey(const Key('board-tool-dock')));
    await tester.tap(find.byKey(const ValueKey('enter-app')));
    await tester.pump();
    expect(aperture(tester).outerRect, before);
    expect(
      aperture(tester).tlRadiusX,
      closeTo(AppTheme.radiusProcessCard * before.width / 260, .000001),
    );
    await tester.pump(const Duration(milliseconds: 180));
    expect(vm.currentLevelId, 'app');
    expect(find.byKey(const Key('portal-incoming')), findsOneWidget);
    expect(find.byKey(const Key('portal-outgoing')), findsOneWidget);
    expect(
      tester
          .widget<LevelPortalTransition>(find.byType(LevelPortalTransition))
          .entering,
      isTrue,
    );
    expect(aperture(tester).width, greaterThan(before.width));
    expect(aperture(tester).width, lessThan(1200));
    expect(
      find.descendant(
        of: find.byType(LevelPortalTransition),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(tester.getRect(find.byKey(const Key('board-tool-dock'))), tools);
    await tester.pumpAndSettle();
    vm.openLevel(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));
    expect(
      tester
          .widget<LevelPortalTransition>(find.byType(LevelPortalTransition))
          .entering,
      isFalse,
    );
    expect(aperture(tester).width, greaterThan(before.width));
    expect(aperture(tester).width, lessThan(1200));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('node-app'))), before);
    expect(vm.prettyJson, data);
    expect(find.byKey(const Key('portal-outgoing')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid nested navigation keeps at most two scenes', (
    tester,
  ) async {
    final vm = await mount(tester);
    for (final level in ['app', 'inner', 'app', null]) {
      vm.openLevel(level);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byKey(const Key('portal-outgoing')), findsOneWidget);
    }
    await tester.pumpAndSettle();
    expect(vm.currentLevelId, isNull);
    expect(find.byKey(const Key('node-app')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion navigates immediately without zoom layers', (
    tester,
  ) async {
    final vm = await mount(tester, reduced: true);
    vm.openLevel('app');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-ui')), findsOneWidget);
    expect(find.byKey(const Key('portal-outgoing')), findsNothing);
    expect(find.byKey(const Key('portal-incoming')), findsNothing);
    vm.openLevel(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-app')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
