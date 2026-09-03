import 'package:foldboard/l10n/l10n.dart';

import 'support/sample_board.dart';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'drag through another card retains pointer, state and front order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = ArchitectureRepository()..clear();
      for (final entry in [('a', 100.0), ('b', 450.0)]) {
        repo.addNode(
          ArchitectureNode(
            id: entry.$1,
            title: entry.$1,
            position: Offset(entry.$2, 200),
          ),
        );
      }
      repo.addEdge(const ArchitectureEdge(id: 'ab', from: 'a', to: 'b'));
      final vm = PlannerViewModel(repository: repo, registerBridge: false);
      addTearDown(vm.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      final card = find.byKey(const ValueKey('node-a'));
      final state = tester.state(card);
      final origin = tester.getRect(card);
      final revisionBeforeDrag = repo.revision;
      final gesture = await tester.startGesture(
        origin.center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      // Bring-to-front must not recreate the recognizer during an active gesture.
      expect(tester.state(card), same(state));
      await gesture.moveTo(origin.center + const Offset(30, 0));
      await tester.pump();
      for (final delta in [100.0, 240.0, 350.0, 360.0, 300.0, 0.0]) {
        await gesture.moveTo(origin.center + Offset(delta, 0));
        await tester.pump();
        expect(tester.getRect(card).topLeft, origin.topLeft + Offset(delta, 0));
        expect(tester.state(card), same(state));
        final positions = tester
            .widgetList<Positioned>(find.byType(Positioned))
            .where((w) => w.key is ValueKey<Key?>)
            .toList();
        expect(positions.last.key, const ValueKey<Key?>(ValueKey('node-a')));
        expect(
          repo.nodes.firstWhere((n) => n.id == 'a').position,
          const Offset(100, 200),
        );
        expect(
          repo.nodes.firstWhere((n) => n.id == 'b').position,
          const Offset(450, 200),
        );
        expect(repo.revision, revisionBeforeDrag);
        expect(tester.takeException(), isNull);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      // Returning to the origin is a no-op: it should not touch persistence.
      expect(repo.revision, revisionBeforeDrag);
      expect(repo.edges.single.id, 'ab');
      // Drop directly over B, then grab A again: the same top card must respond.
      await tester.drag(card, const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(repo.revision, revisionBeforeDrag + 1);
      await tester.drag(card, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(repo.revision, revisionBeforeDrag + 2);
      expect(
        repo.nodes.firstWhere((n) => n.id == 'a').position,
        const Offset(370, 200),
      );
      expect(
        repo.nodes.firstWhere((n) => n.id == 'b').position,
        const Offset(450, 200),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['pan', 'space', 'middle']) {
    for (final overNode in [false, true]) {
      testWidgets('$mode pans 1:1 over ${overNode ? "a node" : "background"}', (
        tester,
      ) async {
        final repository = ArchitectureRepository()..clear();
        repository.addNode(
          const ArchitectureNode(
            id: 'anchor',
            title: 'Anchor',
            position: Offset(500, 200),
          ),
        );
        final vm = PlannerViewModel(repository: repository);
        addTearDown(vm.dispose);
        if (mode == 'pan') vm.setCanvasTool(CanvasTool.pan);
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
        final anchor = find.text('Anchor');
        expect(anchor, findsOneWidget);
        if (mode == 'space') {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        }
        final gesture = await tester.startGesture(
          overNode ? tester.getCenter(anchor) : const Offset(300, 400),
          kind: PointerDeviceKind.mouse,
          buttons: mode == 'middle' ? kMiddleMouseButton : kPrimaryMouseButton,
        );
        // Cross the gesture threshold before measuring steady pointer movement.
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        for (final delta in [const Offset(80, 40), const Offset(-50, -20)]) {
          final before = tester.getTopLeft(anchor);
          await gesture.moveBy(delta);
          await tester.pump();
          final actual = tester.getTopLeft(anchor) - before;
          expect(actual.dx, closeTo(delta.dx, .01));
          expect(actual.dy, closeTo(delta.dy, .01));
          expect(vm.nodes.single.position, const Offset(500, 200));
        }
        await gesture.up();
        if (mode == 'space') {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('trackpad scroll pans both axes and pinch zooms', (tester) async {
    final repository = ArchitectureRepository()..clear();
    repository.addNode(
      const ArchitectureNode(
        id: 'anchor',
        title: 'Anchor',
        position: Offset(500, 200),
      ),
    );
    final vm = PlannerViewModel(repository: repository);
    addTearDown(vm.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: defaultAppLocale,
        home: Scaffold(body: ArchitectureCanvas(viewModel: vm)),
      ),
    );
    await tester.pumpAndSettle();

    final anchor = find.text('Anchor');
    final beforePan = tester.getTopLeft(anchor);
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(300, 400),
        scrollDelta: Offset(70, 45),
        kind: PointerDeviceKind.trackpad,
      ),
    );
    await tester.pump();
    final panDelta = tester.getTopLeft(anchor) - beforePan;
    expect(panDelta.dx, closeTo(-70, .01));
    expect(panDelta.dy, closeTo(-45, .01));

    final beforeZoom = tester
        .getRect(find.byKey(const ValueKey('node-anchor')))
        .size;
    tester.binding.handlePointerEvent(
      const PointerScaleEvent(position: Offset(300, 400), scale: 1.25),
    );
    await tester.pump();
    final afterZoom = tester
        .getRect(find.byKey(const ValueKey('node-anchor')))
        .size;
    expect(afterZoom.width, closeTo(beforeZoom.width * 1.25, .01));
    expect(afterZoom.height, closeTo(beforeZoom.height * 1.25, .01));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final beforeModifiedWheel = tester
        .getRect(find.byKey(const ValueKey('node-anchor')))
        .size;
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(300, 400),
        scrollDelta: Offset(0, -100),
      ),
    );
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    final afterModifiedWheel = tester
        .getRect(find.byKey(const ValueKey('node-anchor')))
        .size;
    expect(afterModifiedWheel.width, greaterThan(beforeModifiedWheel.width));
    expect(repository.nodes.single.position, const Offset(500, 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('node stays attached to pointer at a scaled camera', (
    tester,
  ) async {
    final viewModel = PlannerViewModel(repository: sampleBoard());
    viewModel.openLevel('core-domain');
    final before = viewModel.nodes
        .where((node) => node.id == 'core-service')
        .single
        .position;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: defaultAppLocale,
        home: Scaffold(body: ArchitectureCanvas(viewModel: viewModel)),
      ),
    );

    await tester.pumpAndSettle();
    final scale =
        tester.getSize(find.byKey(const ValueKey('node-core-service'))).width /
        260;
    // Layout size is unscaled; screen-space rect includes the camera transform.
    final screenScale =
        tester.getRect(find.byKey(const ValueKey('node-core-service'))).width /
        260;
    expect(scale, greaterThan(0));
    await tester.drag(find.text('Order service'), const Offset(72, 0));
    await tester.pump();

    final after = viewModel.nodes
        .where((node) => node.id == 'core-service')
        .single
        .position;
    expect(after.dx - before.dx, closeTo(72 / screenScale, 1));
    expect(after.dy, closeTo(before.dy, 1));
  });
}
