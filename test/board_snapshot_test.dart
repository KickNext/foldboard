import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:foldboard/ui/core/board_snapshot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 2x2 image: one opaque red pixel, the rest transparent.
Future<ui.Image> patch() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = const Color(0xFFFF0000),
  );
  return recorder.endRecording().toImage(2, 2);
}

void main() {
  testWidgets('a captured layer is encoded on the theme background', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final layer = await patch();
      addTearDown(layer.dispose);
      final bytes = await pngOnBackground(layer, const Color(0xFF111310));

      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10], reason: 'PNG');

      final decoded = await (await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
      )).getNextFrame();
      addTearDown(decoded.image.dispose);
      expect(decoded.image.width, 2);
      expect(decoded.image.height, 2);

      final pixels = (await decoded.image.toByteData())!;
      // The transparent corner is filled, and it is opaque.
      expect(pixels.getUint32(4 * 3), 0x111310FF);
      expect(pixels.getUint32(0), 0xFF0000FF, reason: 'drawn pixel survives');
    });
  });
}
