import 'dart:ui' as ui;

import 'package:foldboard/ui/core/app_theme.dart';
import 'package:foldboard/ui/features/planner/views/widgets/level_portal_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_portal_position_test.dart' as fixture;

double opacity(WidgetTester tester, String key) =>
    tester.widget<Opacity>(find.byKey(Key(key))).opacity;

void main() {
  for (final viaReference in [false, true]) {
    testWidgets(
      'exit reveals card before cleanup, with no overlapping text: reference=$viaReference',
      (tester) async {
        final vm = await fixture.mount(tester, references: viaReference);
        final data = vm.prettyJson;
        vm.openLevel('app');
        await tester.pumpAndSettle();
        if (viaReference) {
          await tester.tap(find.byKey(const Key('enter-human')));
        } else {
          vm.openLevel(null);
        }
        await tester.pump();
        expect(opacity(tester, 'portal-exit-scene'), 1);
        expect(opacity(tester, 'portal-exit-reveal'), 1);
        final duration = AppTheme.portalTransition.inMicroseconds;
        var previousTime = 0;
        Future<void> at(double fraction) async {
          final nextTime = (duration * fraction).round();
          await tester.pump(Duration(microseconds: nextTime - previousTime));
          previousTime = nextTime;
        }

        await at(.5);
        expect(opacity(tester, 'portal-exit-scene'), inExclusiveRange(0, 1));
        expect(opacity(tester, 'portal-exit-reveal'), 1);
        await at(.65);
        expect(opacity(tester, 'portal-exit-scene'), 0);
        expect(opacity(tester, 'portal-exit-reveal'), 1);
        await at(.8);
        expect(opacity(tester, 'portal-exit-scene'), 0);
        expect(opacity(tester, 'portal-exit-reveal'), inExclusiveRange(0, 1));
        await at(.96);
        expect(opacity(tester, 'portal-exit-reveal'), 0);
        expect(find.byKey(const Key('portal-outgoing')), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('portal-outgoing')), findsNothing);
        expect(vm.prettyJson, data);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'card pixels already match the settled scene before the final frame',
    (tester) async {
      final capture = GlobalKey();
      final nested = ValueNotifier(true);
      addTearDown(nested.dispose);
      const target = Rect.fromLTWH(200, 140, 200, 80);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                height: 400,
                child: RepaintBoundary(
                  key: capture,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: nested,
                    builder: (context, value, _) => LevelPortalTransition(
                      levelId: value ? 'inner' : null,
                      entering: false,
                      portalBounds: target,
                      sourceOrigin: Offset.zero,
                      viewport: const Size(600, 400),
                      child: ColoredBox(
                        color: value
                            ? Colors.blueGrey
                            : AppPalette.light.background,
                        child: value
                            ? const Center(child: Text('Previous scene'))
                            : Stack(
                                children: [
                                  Positioned.fromRect(
                                    rect: target,
                                    child: ColoredBox(
                                      color: AppPalette.light.surface,
                                      child: const Center(
                                        child: Text('Target content'),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
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
      nested.value = false;
      await tester.pump();
      await tester.pump(
        Duration(
          microseconds: (AppTheme.portalTransition.inMicroseconds * .96)
              .round(),
        ),
      );
      Future<List<int>> pixels() async {
        final boundary =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final result = <int>[];
            // Use the card's 16px content padding, excluding its curved rim.
            for (var y = 156; y < 204; y++) {
              for (var x = 216; x < 384; x++) {
                result.add(data.getUint32((y * image.width + x) * 4));
              }
            }
            return result;
          } finally {
            image.dispose();
          }
        }))!;
      }

      final beforeCleanup = await pixels();
      await tester.pumpAndSettle();
      expect(await pixels(), orderedEquals(beforeCleanup));
      expect(tester.takeException(), isNull);
    },
  );
}
