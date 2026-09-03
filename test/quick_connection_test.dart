import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

PlannerViewModel _board() {
  final repository = ArchitectureRepository()..clear();
  repository.addNode(
    const ArchitectureNode(
      id: 'source',
      title: 'Source',
      position: Offset(100, 180),
    ),
  );
  repository.addNode(
    const ArchitectureNode(
      id: 'target',
      title: 'Target',
      position: Offset(520, 180),
    ),
  );
  return PlannerViewModel(repository: repository, registerBridge: false);
}

Widget _app(PlannerViewModel vm) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ListenableBuilder(
      listenable: vm,
      builder: (_, _) => ArchitectureCanvas(viewModel: vm, fitOnStart: true),
    ),
  ),
);

void main() {
  testWidgets('the connector follows the nearest card edge while hovered', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const ValueKey('node-source')));
    final handle = find.byKey(const ValueKey('connection-handle-source'));
    expect(handle, findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    // Hover alone shows nothing: a handle that chases the pointer across
    // every card reads as flicker. The handle belongs to the selection.
    await mouse.moveTo(card.centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(handle, findsNothing);

    await mouse.moveTo(const Offset(900, 600));
    await tester.pump();
    vm.selectCard('source');
    await tester.pump();
    expect(handle, findsOneWidget);
    expect(tester.getCenter(handle), card.centerRight);
    expect(
      find.ancestor(of: handle, matching: find.byType(Tooltip)),
      findsNothing,
    );

    await mouse.moveTo(card.centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(tester.getCenter(handle), card.centerLeft);

    await mouse.moveTo(card.topCenter + const Offset(0, 2));
    await tester.pump();
    expect(tester.getCenter(handle), card.topCenter);

    // Leaving the card keeps the handle, parked on its default side.
    await mouse.moveTo(const Offset(900, 600));
    await tester.pump();
    expect(handle, findsOneWidget);
    expect(tester.getCenter(handle), card.centerRight);
    await mouse.removePointer();
  });

  testWidgets('click connection previews a valid target before selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    final target = tester.getRect(find.byKey(const ValueKey('node-target')));
    vm.startConnection('source');
    await tester.pump();
    expect(vm.canConnectTo('target'), isTrue);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(target.center);
    await tester.pump();

    final preview = find.byKey(const Key('connection-hover-preview'));
    expect(preview, findsOneWidget);
    final painter = tester.widget<CustomPaint>(preview).painter as dynamic;
    expect(
      painter.start as Offset,
      tester.getCenter(find.byKey(const ValueKey('connection-handle-source'))),
    );
    expect(
      painter.end as Offset,
      tester.getCenter(find.byKey(const ValueKey('connection-handle-target'))),
    );

    await mouse.down(target.center);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(vm.connectFrom, isNull);
    expect(vm.edges.single.from, 'source');
    expect(vm.edges.single.to, 'target');
    expect(preview, findsNothing);
    await mouse.removePointer();
  });

  testWidgets('dragging a card edge handle creates an arrow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    vm.selectCard('source');
    await tester.pump();
    final source = tester.getRect(find.byKey(const ValueKey('node-source')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(source.centerRight - const Offset(2, 0));
    await tester.pump();
    final handle = find.byKey(const ValueKey('connection-handle-source'));
    final target = find.byKey(const ValueKey('node-target'));
    expect(handle, findsOneWidget);

    await mouse.down(tester.getCenter(handle));
    final targetRect = tester.getRect(target);
    await mouse.moveTo(targetRect.centerRight - const Offset(4, 0));
    await tester.pump();
    expect(find.byKey(const Key('connection-drag-preview')), findsOneWidget);
    expect(vm.connectFrom, 'source');
    final preview = tester.widget<CustomPaint>(
      find.byKey(const Key('connection-drag-preview')),
    );
    final painter = preview.painter as dynamic;
    expect(painter.end as Offset, targetRect.centerRight);
    expect(painter.endDirection as Offset, const Offset(-1, 0));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(vm.connectFrom, isNull);
    expect(vm.edges, hasLength(1));
    expect(vm.edges.single.from, 'source');
    expect(vm.edges.single.to, 'target');
  });

  testWidgets('drag preview exits and enters all four selected sides', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    vm.selectCard('source');
    await tester.pump();
    final source = tester.getRect(find.byKey(const ValueKey('node-source')));
    final target = tester.getRect(find.byKey(const ValueKey('node-target')));
    final handle = find.byKey(const ValueKey('connection-handle-source'));
    final cases =
        <
          ({
            Offset sourcePoint,
            Offset targetPoint,
            Offset startDirection,
            Offset endDirection,
          })
        >[
          (
            sourcePoint: source.centerLeft + const Offset(2, 0),
            targetPoint: target.centerRight - const Offset(4, 0),
            startDirection: const Offset(-1, 0),
            endDirection: const Offset(-1, 0),
          ),
          (
            sourcePoint: source.centerRight - const Offset(2, 0),
            targetPoint: target.centerLeft + const Offset(4, 0),
            startDirection: const Offset(1, 0),
            endDirection: const Offset(1, 0),
          ),
          (
            sourcePoint: source.topCenter + const Offset(0, 2),
            targetPoint: target.bottomCenter - const Offset(0, 4),
            startDirection: const Offset(0, -1),
            endDirection: const Offset(0, -1),
          ),
          (
            sourcePoint: source.bottomCenter - const Offset(0, 2),
            targetPoint: target.topCenter + const Offset(0, 4),
            startDirection: const Offset(0, 1),
            endDirection: const Offset(0, 1),
          ),
        ];

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(900, 600));
    for (final item in cases) {
      await mouse.moveTo(item.sourcePoint);
      await tester.pump();
      expect(handle, findsOneWidget);
      await mouse.down(tester.getCenter(handle));
      await mouse.moveTo(item.targetPoint);
      await tester.pump();

      final preview = tester.widget<CustomPaint>(
        find.byKey(const Key('connection-drag-preview')),
      );
      final painter = preview.painter as dynamic;
      expect(painter.startDirection as Offset, item.startDirection);
      expect(painter.endDirection as Offset, item.endDirection);

      await mouse.moveTo(const Offset(900, 600));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(vm.connectFrom, isNull);
    }
    await mouse.removePointer();
  });

  testWidgets('dropping the edge handle on empty canvas cancels cleanly', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    vm.selectCard('source');
    await tester.pump();
    final source = tester.getRect(find.byKey(const ValueKey('node-source')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(source.centerRight - const Offset(2, 0));
    await tester.pump();
    final handle = find.byKey(const ValueKey('connection-handle-source'));
    await mouse.down(tester.getCenter(handle));
    await mouse.moveTo(const Offset(500, 500));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();

    expect(vm.edges, isEmpty);
    expect(vm.connectFrom, isNull);
    expect(find.byKey(const Key('connection-drag-preview')), findsNothing);
  });
}
