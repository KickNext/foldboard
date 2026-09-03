import 'package:foldboard/ui/features/planner/views/widgets/reference_portal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_portal_position_test.dart' as fixture;

double openness(WidgetTester tester, String id) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(ValueKey('reference-portal-$id')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is ReferencePortalPainter,
      ),
    ),
  );
  return (paint.painter! as ReferencePortalPainter).openness;
}

void main() {
  testWidgets('external reference can move without moving its original', (
    tester,
  ) async {
    final vm = await fixture.mount(
      tester,
      initialLevel: 'app',
      references: true,
    );
    final original = vm.nodes.firstWhere((node) => node.id == 'human').position;
    final reference = find.byKey(const ValueKey('node-human'));
    final before = fixture.card(tester, 'human');

    await tester.drag(reference, const Offset(80, 50));
    await tester.pumpAndSettle();

    expect(
      fixture.card(tester, 'human').topLeft,
      before.topLeft + const Offset(80, 50),
    );
    expect(
      vm.nodes.firstWhere((node) => node.id == 'human').position,
      original,
    );
    expect(vm.repository.referencePositions('app')['human'], isNot(original));
    expect(tester.takeException(), isNull);
  });

  for (final reduced in [false, true]) {
    const id = 'human';
    testWidgets(
      'external reference selects on click and exits on double click: reduced=$reduced',
      (tester) async {
        final vm = await fixture.mount(
          tester,
          initialLevel: 'app',
          references: true,
          reduced: reduced,
        );
        final data = vm.prettyJson;
        final source = fixture.card(tester, id);
        final point = source.topCenter + const Offset(0, 20);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.down(point, timeStamp: const Duration(milliseconds: 1000));
        await mouse.up(timeStamp: const Duration(milliseconds: 1015));
        await tester.pump(const Duration(milliseconds: 80));
        expect(vm.currentLevelId, 'app');
        expect(vm.selectedId ?? vm.selectedGroupId, id);
        expect(find.byKey(const Key('portal-outgoing')), findsNothing);
        expect(fixture.card(tester, id), rectMoreOrLessEquals(source));

        await mouse.down(point, timeStamp: const Duration(milliseconds: 1080));
        await mouse.up(timeStamp: const Duration(milliseconds: 1095));
        await tester.pump();
        expect(vm.currentLevelId, isNull);
        expect(vm.selectedId ?? vm.selectedGroupId, id);
        expect(
          reduced ? fixture.card(tester, id) : fixture.incomingCard(tester, id),
          rectMoreOrLessEquals(source),
        );
        await tester.pumpAndSettle();
        await mouse.removePointer();
        expect(vm.prettyJson, data);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final hoverTime in [80, 300]) {
    testWidgets(
      'exit retains painted reference hover pose after $hoverTime ms',
      (tester) async {
        final vm = await fixture.mount(
          tester,
          initialLevel: 'app',
          references: true,
        );
        final data = vm.prettyJson;
        final source = fixture.card(tester, 'human');
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(source.center);
        await tester.pump();
        await tester.pump(Duration(milliseconds: hoverTime));
        final before = openness(tester, 'human');
        expect(before, greaterThan(0));
        if (hoverTime == 80) expect(before, lessThan(1));
        vm.openReference('human');
        await tester.pump();
        expect(openness(tester, 'human'), before);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 120));
        expect(openness(tester, 'human'), before);
        await tester.pump(const Duration(milliseconds: 90));
        expect(openness(tester, 'human'), before);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('portal-outgoing')), findsNothing);
        expect(fixture.card(tester, 'human'), rectMoreOrLessEquals(source));
        expect(vm.prettyJson, data);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
