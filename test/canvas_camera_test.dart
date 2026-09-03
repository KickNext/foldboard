import 'dart:ui';

import 'package:foldboard/ui/features/planner/view_models/canvas_camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resizing the visible window keeps map position and zoom unchanged', () {
    final camera = CanvasCamera(scale: .6, translation: const Offset(-120, 70));
    addTearDown(camera.dispose);
    camera.setViewport(const Size(1200, 800));
    const point = Offset(500, 400);
    final before = camera.worldToScreen(point);
    for (final size in [
      const Size(850, 800),
      const Size(600, 360),
      const Size(1200, 800),
    ]) {
      camera.setViewport(size);
      expect(camera.worldToScreen(point), before);
      expect(camera.scale, .6);
      expect(camera.viewport, size);
    }
  });
  test('zoom keeps the world point under the cursor fixed', () {
    final camera = CanvasCamera(scale: .6, translation: const Offset(-120, 70))
      ..setViewport(const Size(1200, 800));
    const cursor = Offset(830, 260);
    final worldBefore = camera.screenToWorld(cursor);

    camera.zoomAt(cursor, 1.45);

    final worldAfter = camera.screenToWorld(cursor);
    expect(worldAfter.dx, closeTo(worldBefore.dx, .0001));
    expect(worldAfter.dy, closeTo(worldBefore.dy, .0001));
  });

  test('visible world rect follows an unrestricted camera', () {
    final camera = CanvasCamera(scale: .5)
      ..setViewport(const Size(1000, 600))
      ..pan(const Offset(8000, -5000));

    final visible = camera.visibleWorldRect;
    expect(visible.width, 2000);
    expect(visible.height, 1200);
    expect(visible.left, lessThan(-10000));
    expect(visible.top, greaterThan(9000));
  });
}
