import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Encode a captured board layer as a PNG on an opaque background.
///
/// The board layer paints only the grid, arrows and cards, so the raw capture
/// is transparent wherever the canvas shows through. Diagrams are read on a
/// white or dark page, not on a checkerboard, so the theme background is
/// composited in rather than left to the viewer.
Future<List<int>> pngOnBackground(ui.Image layer, Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final area = Rect.fromLTWH(
    0,
    0,
    layer.width.toDouble(),
    layer.height.toDouble(),
  );
  canvas.drawRect(area, Paint()..color = color);
  canvas.drawImage(layer, Offset.zero, Paint());
  final picture = recorder.endRecording();
  final composed = await picture.toImage(layer.width, layer.height);
  try {
    final data = await composed.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('The image could not be encoded');
    return data.buffer.asUint8List();
  } finally {
    composed.dispose();
    picture.dispose();
  }
}
