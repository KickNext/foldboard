import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';

import 'support/project_stores.dart';

import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/planner_page.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/planner/views/widgets/level_portal_transition.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Rect card(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('node-$id')));
Rect viewport(WidgetTester tester) =>
    tester.getRect(find.byType(ArchitectureCanvas));
LevelPortalTransition transition(WidgetTester tester) =>
    tester.widget<LevelPortalTransition>(find.byType(LevelPortalTransition));
Rect portalTarget(WidgetTester tester) => transition(tester).portalBounds!
    .shift(transition(tester).destinationOrigin ?? viewport(tester).topLeft);
Rect incomingCard(WidgetTester tester, String id) => tester.getRect(
  find.descendant(
    of: find.byKey(const Key('portal-incoming')),
    matching: find.byKey(ValueKey('node-$id')),
  ),
);
Rect aperture(WidgetTester tester) =>
    (tester.widget<ClipRRect>(find.byKey(const Key('portal-aperture'))).clipper!
            as PortalApertureClipper)
        .aperture
        .outerRect
        .shift(viewport(tester).topLeft);

Future<PlannerViewModel> mount(
  WidgetTester tester, {
  String? initialLevel,
  bool references = false,
  bool reduced = false,
  ValueNotifier<EdgeInsets>? padding,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final store = MemoryProjectStore()
    ..value = jsonEncode({
      'groups': [
        {'id': 'app', 'title': 'App', 'x': 700, 'y': 260},
        {
          'id': 'inner',
          'title': 'Inner',
          'parentId': 'app',
          'x': 1100,
          'y': 300,
        },
        {'id': 'other', 'title': 'Other', 'x': 150, 'y': 750},
        {
          'id': 'remote',
          'title': 'Remote',
          'parentId': 'other',
          'x': 900,
          'y': 300,
        },
      ],
      'nodes': [
        {'id': 'human', 'title': 'Human', 'x': 150, 'y': 260},
        {'id': 'ui', 'title': 'UI', 'parentId': 'app', 'x': 300, 'y': 300},
        {
          'id': 'leaf',
          'title': 'Leaf',
          'parentId': 'inner',
          'x': 400,
          'y': 300,
        },
        {
          'id': 'remote-leaf',
          'title': 'Remote leaf',
          'parentId': 'remote',
          'x': 300,
          'y': 300,
        },
      ],
      'edges': [
        if (references) ...[
          {'id': 'input', 'from': 'human', 'to': 'ui'},
          {'id': 'remote-input', 'from': 'remote-leaf', 'to': 'ui'},
        ],
      ],
    });
  final repo = ArchitectureRepository(store: store);
  addTearDown(repo.dispose);
  final vm = PlannerViewModel(repository: repo, registerBridge: false);
  addTearDown(vm.dispose);
  if (initialLevel != null) vm.openLevel(initialLevel);
  final insets = padding ?? ValueNotifier(EdgeInsets.zero);
  if (padding == null) addTearDown(insets.dispose);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ValueListenableBuilder<EdgeInsets>(
        valueListenable: insets,
        builder: (_, value, child) => Padding(padding: value, child: child),
        child: PlannerPage(viewModel: vm),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

Future<void> pan(WidgetTester tester, Offset delta) async {
  final mouse = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kMiddleMouseButton,
  );
  await mouse.down(viewport(tester).center);
  await mouse.moveBy(delta);
  await mouse.up();
  await tester.pumpAndSettle();
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'reference holds screen position after zoom, pan and header relayout: reduced=$reduced',
      (tester) async {
        final padding = ValueNotifier(
          const EdgeInsets.only(top: 20, bottom: 50),
        );
        addTearDown(padding.dispose);
        final vm = await mount(
          tester,
          references: true,
          padding: padding,
          reduced: reduced,
        );
        final data = vm.prettyJson;
        vm.openLevel('app');
        await tester.pumpAndSettle();
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: card(tester, 'human').center,
            scrollDelta: const Offset(0, -140),
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
        await pan(tester, const Offset(55, 40));
        final source = card(tester, 'human');
        padding.value = const EdgeInsets.only(top: 55, bottom: 15);
        vm.openReference('human');
        await tester.pump();
        expect(
          reduced ? card(tester, 'human') : incomingCard(tester, 'human'),
          rectMoreOrLessEquals(source),
        );
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          reduced ? card(tester, 'human') : incomingCard(tester, 'human'),
          rectMoreOrLessEquals(source),
        );
        await tester.pumpAndSettle();
        expect(card(tester, 'human'), rectMoreOrLessEquals(source));
        expect(card(tester, 'app').width, closeTo(source.width, .0001));
        expect(vm.selectedId, 'human');
        expect(vm.prettyJson, data);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'reference exit keeps the clicked card fixed and aligns its original',
    (tester) async {
      final vm = await mount(tester, references: true);
      final data = vm.prettyJson;
      vm.openLevel('app');
      await tester.pumpAndSettle();
      final child = card(tester, 'ui');
      final source = card(tester, 'human');
      await tester.tap(find.byKey(const Key('enter-human')));
      await tester.pump();
      expect(vm.currentLevelId, isNull);
      expect(vm.selectedId, 'human');
      expect(vm.cameraTargetId, isNull);
      expect(transition(tester).entering, isFalse);
      expect(portalTarget(tester), rectMoreOrLessEquals(source));
      expect(
        transition(tester).portalRadius,
        closeTo(AppTheme.radiusCard * source.width / 260, .0001),
      );
      expect(incomingCard(tester, 'human'), rectMoreOrLessEquals(source));
      await tester.pump(const Duration(milliseconds: 120));
      expect(incomingCard(tester, 'human'), rectMoreOrLessEquals(source));
      await tester.pumpAndSettle();
      expect(card(tester, 'human'), rectMoreOrLessEquals(source));
      final parent = card(tester, 'app');
      vm.openLevel('app');
      await tester.pumpAndSettle();
      expect(card(tester, 'ui'), rectMoreOrLessEquals(child));
      vm.openLevel(null);
      await tester.pump();
      expect(
        transition(tester).portalBounds!.shift(viewport(tester).topLeft),
        rectMoreOrLessEquals(parent),
      );
      await tester.pumpAndSettle();
      expect(vm.prettyJson, data);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offscreen original aligns to the clicked reference instead of centering',
    (tester) async {
      final vm = await mount(tester, references: true);
      await pan(tester, const Offset(1400, 0));
      vm.openLevel('app');
      await tester.pumpAndSettle();
      final source = card(tester, 'human');
      await tester.tap(find.byKey(const Key('enter-human')));
      await tester.pumpAndSettle();
      expect(card(tester, 'human'), rectMoreOrLessEquals(source));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reference to an unvisited branch keeps scale and targets original',
    (tester) async {
      final vm = await mount(tester, references: true, initialLevel: 'app');
      final source = card(tester, 'remote-leaf');
      final sourceWidth = source.width;
      // Explicit Open follows the same anchored route as a double click.
      await tester.tap(find.byKey(const Key('enter-remote-leaf')));
      await tester.pump();
      expect(vm.currentLevelId, 'remote');
      expect(transition(tester).entering, isFalse);
      expect(
        transition(tester).portalBounds!.width,
        closeTo(sourceWidth, .0001),
      );
      await tester.pumpAndSettle();
      expect(card(tester, 'remote-leaf').width, closeTo(sourceWidth, .0001));
      expect(card(tester, 'remote-leaf'), rectMoreOrLessEquals(source));
      expect(vm.selectedId, 'remote-leaf');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('entry fits the destination viewport, not the previous level', (
    tester,
  ) async {
    final vm = await mount(tester);
    final source = card(tester, 'app');
    await tester.tap(find.byKey(const Key('enter-app')));
    await tester.pump();
    expect(aperture(tester), rectMoreOrLessEquals(source));
    expect(card(tester, 'app'), rectMoreOrLessEquals(source));
    await tester.pumpAndSettle();
    final entered = card(tester, 'ui');
    expect(vm.currentLevelId, 'app');
    await mount(tester, initialLevel: 'app');
    expect(card(tester, 'ui'), rectMoreOrLessEquals(entered));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'source stays fixed when layout moves without changing its height',
    (tester) async {
      final padding = ValueNotifier(const EdgeInsets.only(top: 10, bottom: 40));
      addTearDown(padding.dispose);
      final vm = await mount(tester, padding: padding);
      final source = card(tester, 'app');
      padding.value = const EdgeInsets.only(top: 40, bottom: 10);
      vm.openLevel('app');
      await tester.pump();
      expect(aperture(tester), rectMoreOrLessEquals(source));
      expect(card(tester, 'app'), rectMoreOrLessEquals(source));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back lands on its parent card; re-entry restores child pan and zoom',
    (tester) async {
      final vm = await mount(tester);
      final data = vm.prettyJson;
      await pan(tester, const Offset(-60, 35));
      final parentCard = card(tester, 'app');
      vm.openLevel('app');
      await tester.pumpAndSettle();
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: viewport(tester).center,
          scrollDelta: const Offset(0, -100),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pumpAndSettle();
      await pan(tester, const Offset(90, 55));
      final childCard = card(tester, 'ui');
      vm.openLevel(null);
      await tester.pump();
      expect(transition(tester).entering, isFalse);
      expect(
        transition(tester).portalBounds!.shift(viewport(tester).topLeft),
        rectMoreOrLessEquals(parentCard),
      );
      await tester.pump(
        AppTheme.portalTransition - const Duration(milliseconds: 1),
      );
      expect(aperture(tester), rectMoreOrLessEquals(parentCard, epsilon: .01));
      await tester.pumpAndSettle();
      expect(card(tester, 'app'), rectMoreOrLessEquals(parentCard));
      vm.openLevel('app');
      await tester.pumpAndSettle();
      expect(card(tester, 'ui'), rectMoreOrLessEquals(childCard));
      expect(vm.prettyJson, data);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nested back and root jump each target the correct containing card',
    (tester) async {
      final vm = await mount(tester);
      final rootCard = card(tester, 'app');
      vm.openLevel('app');
      await tester.pumpAndSettle();
      final innerCard = card(tester, 'inner');
      vm.openLevel('inner');
      await tester.pump();
      expect(aperture(tester), rectMoreOrLessEquals(innerCard));
      await tester.pumpAndSettle();
      vm.openLevel('app');
      await tester.pump();
      expect(
        transition(tester).portalBounds!.shift(viewport(tester).topLeft),
        rectMoreOrLessEquals(innerCard),
      );
      await tester.pumpAndSettle();
      vm.openLevel('inner');
      await tester.pumpAndSettle();
      vm.openLevel(null);
      await tester.pump();
      expect(
        transition(tester).portalBounds!.shift(viewport(tester).topLeft),
        rectMoreOrLessEquals(rootCard),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search across branches does not invent a central portal', (
    tester,
  ) async {
    final vm = await mount(tester, initialLevel: 'app');
    vm.revealObject('remote-leaf');
    await tester.pump();
    expect(vm.currentLevelId, 'remote');
    expect(find.byKey(const Key('portal-aperture')), findsNothing);
    await tester.pumpAndSettle();
    expect(
      card(tester, 'remote-leaf').center,
      offsetMoreOrLessEquals(viewport(tester).center),
    );
    expect(vm.selectedId, 'remote-leaf');
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the current level does not reset its camera', (
    tester,
  ) async {
    final vm = await mount(tester, initialLevel: 'app');
    await pan(tester, const Offset(50, 60));
    final before = card(tester, 'ui');
    final request = vm.cameraRequestVersion;
    vm.openLevel('app');
    await tester.pumpAndSettle();
    expect(vm.cameraRequestVersion, request);
    expect(card(tester, 'ui'), rectMoreOrLessEquals(before));
  });

  testWidgets(
    'resize ends the flight cleanly and restores parent center at its new size',
    (tester) async {
      final vm = await mount(tester);
      final before = card(tester, 'app');
      final relativeCenter = before.center - viewport(tester).center;
      vm.openLevel('app');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.binding.setSurfaceSize(const Size(900, 850));
      await tester.pump();
      expect(find.byKey(const Key('portal-aperture')), findsNothing);
      await tester.pumpAndSettle();
      vm.openLevel(null);
      await tester.pumpAndSettle();
      expect(card(tester, 'app').width, closeTo(before.width, .000001));
      expect(
        card(tester, 'app').center - viewport(tester).center,
        offsetMoreOrLessEquals(relativeCenter),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offscreen source skips the flight instead of fabricating an anchor',
    (tester) async {
      final vm = await mount(tester);
      await pan(tester, const Offset(-2000, 0));
      vm.openLevel('app');
      await tester.pump();
      expect(find.byKey(const Key('portal-aperture')), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
