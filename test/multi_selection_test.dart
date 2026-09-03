import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PlannerViewModel _board() {
  final repository = ArchitectureRepository()..clear();
  repository.addNode(
    const ArchitectureNode(id: 'a', title: 'A', position: Offset(100, 120)),
  );
  repository.addNode(
    const ArchitectureNode(id: 'b', title: 'B', position: Offset(440, 120)),
  );
  repository.addNode(
    const ArchitectureNode(id: 'c', title: 'C', position: Offset(780, 120)),
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
  test('selection set supports toggle, bulk movement and deletion', () {
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });

    vm.selectCard('a');
    vm.toggleCardSelection('b');
    expect(vm.selectedCardIds, {'a', 'b'});
    expect(vm.hasMultipleSelection, isTrue);

    vm.repository.beginTransaction();
    vm.nudgeSelection(const Offset(20, 10));
    vm.repository.endTransaction();
    expect(
      vm.nodes.firstWhere((node) => node.id == 'a').position,
      const Offset(120, 130),
    );
    expect(
      vm.nodes.firstWhere((node) => node.id == 'b').position,
      const Offset(460, 130),
    );
    vm.undo();
    expect(
      vm.nodes.firstWhere((node) => node.id == 'a').position,
      const Offset(100, 120),
    );

    vm.deleteSelected();
    expect(vm.nodes.map((node) => node.id), ['c']);
    expect(vm.hasSelection, isFalse);
  });

  test('copy and paste preserves spacing between selected roots', () {
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    vm.selectCards(['a', 'b']);
    expect(vm.copySelection(), isTrue);
    expect(vm.paste(offsetFromSource: true), isTrue);
    expect(vm.selectedCardIds.length, 2);
    final copies = vm.nodes
        .where((node) => vm.selectedCardIds.contains(node.id))
        .toList();
    expect((copies[0].position.dx - copies[1].position.dx).abs(), 340);
  });

  testWidgets('Shift click adds a card and plain click returns to one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('node-a')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.byKey(const ValueKey('node-b')));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(vm.selectedCardIds, {'a', 'b'});

    await tester.tap(find.byKey(const ValueKey('node-c')));
    await tester.pump();
    expect(vm.selectedCardIds, {'c'});
  });

  testWidgets('one click on empty canvas clears the selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board()..selectCard('a');
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    final selectedCard = tester.getRect(find.byKey(const ValueKey('node-a')));
    await tester.tapAt(selectedCard.bottomCenter + const Offset(0, 40));
    await tester.pump();

    expect(vm.hasSelection, isFalse);
  });

  testWidgets('Plain drag on empty canvas selects cards with a marquee', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board();
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    final a = tester.getRect(find.byKey(const ValueKey('node-a')));
    final b = tester.getRect(find.byKey(const ValueKey('node-b')));
    final gesture = await tester.startGesture(a.topLeft - const Offset(10, 10));
    await gesture.moveTo(b.bottomRight + const Offset(10, 10));
    await tester.pump();
    expect(find.byKey(const Key('selection-marquee')), findsOneWidget);
    await gesture.up();
    await tester.pump();

    expect(vm.selectedCardIds, {'a', 'b'});
    expect(find.byKey(const Key('selection-marquee')), findsNothing);
  });

  testWidgets('dragging one selected card moves the whole selection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final vm = _board()..selectCards(['a', 'b']);
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    await tester.pumpWidget(_app(vm));
    await tester.pumpAndSettle();

    final beforeA = vm.nodes.firstWhere((node) => node.id == 'a').position;
    final beforeB = vm.nodes.firstWhere((node) => node.id == 'b').position;

    await tester.drag(
      find.byKey(const ValueKey('node-a')),
      const Offset(50, 30),
    );
    await tester.pump();

    final afterA = vm.nodes.firstWhere((node) => node.id == 'a').position;
    final afterB = vm.nodes.firstWhere((node) => node.id == 'b').position;
    expect(afterA, isNot(beforeA));
    expect(afterA - beforeA, afterB - beforeB);
    vm.undo();
    expect(vm.nodes.firstWhere((node) => node.id == 'a').position, beforeA);
    expect(vm.nodes.firstWhere((node) => node.id == 'b').position, beforeB);
  });
}
