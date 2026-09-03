import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/views/widgets/reference_portal.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ReferencePortalPainter painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is ReferencePortalPainter,
              ),
            )
            .painter!
        as ReferencePortalPainter;

void main() {
  test(
    'all reflected corners share the card corner centers at every hover depth',
    () {
      const size = Size(260, 118);
      for (final t in [0.0, .25, .5, .75, 1.0]) {
        final frames = ReferencePortalPainter.reflections(size, t);
        expect(frames.length, 3);
        for (final frame in frames) {
          final gap = -frame.left;
          expect(frame.top, -gap);
          expect(frame.right, size.width + gap);
          expect(frame.bottom, size.height + gap);
          expect(frame.tlRadiusX, AppTheme.radiusCard + gap);
          expect(frame.tlRadiusY, AppTheme.radiusCard + gap);
          expect(frame.brRadiusX, AppTheme.radiusCard + gap);
          expect(frame.brRadiusY, AppTheme.radiusCard + gap);
          expect(gap, lessThan(AppTheme.referencePortalExtent));
        }
      }
      expect(
        ReferencePortalPainter.reflections(size, 1).last.width,
        greaterThan(ReferencePortalPainter.reflections(size, 0).last.width),
      );
    },
  );

  for (final reduced in [false, true]) {
    testWidgets(
      'outward hover is finite, keeps text still and respects reduced motion: $reduced',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 260,
                    height: 118,
                    child: ReferencePortal(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                        child: const Center(
                          child: Text('Original card', key: Key('content')),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bounds = tester.getRect(find.byType(ReferencePortal));
        final textBounds = tester.getRect(find.byKey(const Key('content')));
        expect(painter(tester).openness, 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(bounds.center);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(painter(tester).openness, greaterThan(0));
        if (!reduced) expect(painter(tester).openness, lessThan(1));
        await tester.pumpAndSettle();
        expect(painter(tester).openness, 1);
        expect(tester.getRect(find.byType(ReferencePortal)), bounds);
        expect(tester.getRect(find.byKey(const Key('content'))), textBounds);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await tester.tapAt(bounds.center);
        expect(taps, 1);
        // Decorations outside the original bounds must not steal canvas input.
        await tester.tapAt(bounds.topLeft - const Offset(10, 10));
        expect(taps, 1);
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(painter(tester).openness, 0);
        expect(tester.binding.hasScheduledFrame, isFalse);
        await mouse.removePointer();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
