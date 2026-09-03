import 'package:foldboard/ui/core/app_theme.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation has a soft start, monotonic travel and a slow landing', () {
    const curve = AppTheme.portalCurve;
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    var previous = 0.0;
    for (var i = 1; i <= 100; i++) {
      final value = curve.transform(i / 100);
      expect(value, inInclusiveRange(previous, 1));
      previous = value;
    }
    final firstStep = curve.transform(.05);
    final travelStep = curve.transform(.25) - curve.transform(.2);
    final lastStep = 1 - curve.transform(.95);
    expect(firstStep, lessThan(travelStep * .3));
    expect(lastStep, lessThan(travelStep * .1));
    expect(curve.transform(.5), inExclusiveRange(.75, .85));
    expect(AppTheme.portalTransition, const Duration(milliseconds: 420));
  });

  test(
    'hover retains its existing curve; exit text handoff never overlaps',
    () {
      const originalHover = Cubic(.22, .8, .18, 1);
      for (var i = 0; i <= 100; i++) {
        final t = i / 100;
        expect(
          AppTheme.portalHoverCurve.transform(t),
          originalHover.transform(t),
        );
        final oldScene = 1 - AppTheme.portalExitVeil.transform(t);
        final revealedCard = AppTheme.portalExitReveal.transform(t);
        expect(oldScene * revealedCard, 0);
      }
      expect(AppTheme.portalExitReveal.transform(.96), 1);
    },
  );
}
