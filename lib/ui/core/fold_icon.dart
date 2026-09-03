import 'package:flutter/material.dart';

/// The fold glyph: a frame with an inner frame receding toward its right
/// edge, echoing the portal motif on fold cards. Folds get this one glyph
/// everywhere — dock, inspector, search — so the concept stays learnable.
class FoldIcon extends StatelessWidget {
  const FoldIcon({super.key, this.size = 20, this.color, this.add = false});

  final double size;
  final Color? color;

  /// Draws a plus in the outer frame's clear space: "add fold".
  final bool add;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color;
    return CustomPaint(
      size: Size.square(size),
      painter: _FoldIconPainter(
        color: resolved ?? const Color(0xFF808080),
        add: add,
      ),
    );
  }
}

class _FoldIconPainter extends CustomPainter {
  _FoldIconPainter({required this.color, required this.add});
  final Color color;
  final bool add;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .09
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * .07, s * .17, s * .86, s * .66),
        Radius.circular(s * .16),
      ),
      stroke,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * .48, s * .34, s * .32, s * .32),
        Radius.circular(s * .1),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .08
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    if (add) {
      final centre = Offset(s * .28, s * .5);
      final reach = s * .11;
      final plus = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * .09
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawLine(
        centre - Offset(reach, 0),
        centre + Offset(reach, 0),
        plus,
      );
      canvas.drawLine(
        centre - Offset(0, reach),
        centre + Offset(0, reach),
        plus,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FoldIconPainter old) =>
      old.color != color || old.add != add;
}
