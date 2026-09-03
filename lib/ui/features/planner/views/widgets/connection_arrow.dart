import 'dart:math' as math;
import 'dart:ui';

import '../../../../core/app_theme.dart';

/// Compact tapered head with curved shoulders and a recessed tail.
Path connectionArrowHead(Offset tip, double angle, double zoom) {
  final size = math.sqrt(zoom).clamp(.7, 1.15);
  final direction = Offset.fromDirection(angle);
  final normal = Offset(-direction.dy, direction.dx);
  Offset at(double x, double y) =>
      tip + direction * (x * size) + normal * (y * size);
  final length = AppTheme.arrowHeadLength;
  final width = AppTheme.arrowHeadHalfWidth;
  final upper = at(-length, -width);
  final lower = at(-length, width);
  final upperShoulder = at(-length * .42, -width * .36);
  final lowerShoulder = at(-length * .42, width * .36);
  final tail = at(-length * .7, 0);
  return Path()
    ..moveTo(tip.dx, tip.dy)
    ..quadraticBezierTo(lowerShoulder.dx, lowerShoulder.dy, lower.dx, lower.dy)
    ..lineTo(tail.dx, tail.dy)
    ..lineTo(upper.dx, upper.dy)
    ..quadraticBezierTo(upperShoulder.dx, upperShoulder.dy, tip.dx, tip.dy)
    ..close();
}
