import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

class CanvasCamera extends ChangeNotifier {
  CanvasCamera({this._scale = .72, this._translation = const Offset(-180, 40)});

  static const double minScale = .00001;
  static const double maxScale = 2.4;
  double _scale;
  Offset _translation;
  Size _viewport = Size.zero;

  double get scale => _scale;
  Offset get translation => _translation;
  Size get viewport => _viewport;

  Rect get visibleWorldRect {
    if (_viewport.isEmpty) return Rect.zero;
    final topLeft = screenToWorld(Offset.zero);
    final bottomRight = screenToWorld(_viewport.bottomRight(Offset.zero));
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void setViewport(Size value) {
    if (value == _viewport) return;
    // Opening/closing details only changes the visible window, not the map.
    _viewport = value;
  }

  Offset worldToScreen(Offset world) => world * _scale + _translation;
  Offset screenToWorld(Offset screen) => (screen - _translation) / _scale;

  void pan(Offset screenDelta) {
    _translation += screenDelta;
    notifyListeners();
  }

  void setTransform({required double scale, required Offset translation}) {
    _scale = scale.clamp(minScale, maxScale);
    _translation = translation;
    notifyListeners();
  }

  void zoomAt(Offset screenAnchor, double targetScale) {
    final next = targetScale.clamp(minScale, maxScale);
    if ((next - _scale).abs() <= _scale.abs() * 1e-10) return;
    final worldAnchor = screenToWorld(screenAnchor);
    _scale = next;
    _translation = screenAnchor - worldAnchor * _scale;
    notifyListeners();
  }

  void zoomBy(Offset screenAnchor, double factor) =>
      zoomAt(screenAnchor, _scale * factor);

  void fitBounds(Rect bounds, {double padding = 80}) {
    if (_viewport.isEmpty || bounds.isEmpty) return;
    final availableWidth = math.max(1.0, _viewport.width - padding * 2);
    final availableHeight = math.max(1.0, _viewport.height - padding * 2);
    _scale = math
        .min(availableWidth / bounds.width, availableHeight / bounds.height)
        .clamp(minScale, 1.0);
    _translation = _viewport.center(Offset.zero) - bounds.center * _scale;
    notifyListeners();
  }
}
