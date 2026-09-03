import 'dart:math' as math;

import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/edge_routes.dart';
import 'package:foldboard/ui/features/planner/views/widgets/connection_arrow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arrowhead is closed, symmetric and points along the path', () {
    for (final angle in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
      final tip = const Offset(100, 100);
      final path = connectionArrowHead(tip, angle, 1);
      final metric = path.computeMetrics().single;
      expect(metric.isClosed, isTrue);
      expect(
        (metric.getTangentForOffset(0)!.position - tip).distance,
        lessThan(.001),
      );
      final direction = Offset.fromDirection(angle);
      expect(path.contains(tip - direction * 4), isTrue);
      expect(path.contains(tip + direction * 2), isFalse);
    }
  });

  test('arrowheads remain bounded at every supported zoom', () {
    for (final zoom in [.12, .25, .72, 1.0, 2.4]) {
      final bounds = connectionArrowHead(Offset.zero, 0, zoom).getBounds();
      expect(bounds.width, inInclusiveRange(6.2, 10.4));
      expect(bounds.height, inInclusiveRange(6.2, 10.4));
    }
  });

  test('curved connections use exact terminal tangent, not sampled chord', () {
    for (final position in [const Offset(310, 80), const Offset(40, 190)]) {
      final route = EdgeRouter()
          .route(
            [
              const ArchitectureNode(id: 'a', title: 'a'),
              ArchitectureNode(id: 'b', title: 'b', position: position),
            ],
            [const ArchitectureEdge(id: 'ab', from: 'a', to: 'b')],
          )
          .single;
      expect(route.angle, closeTo(position.dx > 260 ? 0 : math.pi / 2, 1e-9));
      final metric = route.path.computeMetrics().single;
      final nearEnd = metric.getTangentForOffset(metric.length - 8)!.position;
      final normal = Offset.fromDirection(route.angle + math.pi / 2);
      final delta = nearEnd - route.tip;
      // The curve continues to the endpoint; there is no straight landing stub.
      expect(
        (delta.dx * normal.dx + delta.dy * normal.dy).abs(),
        greaterThan(.05),
      );
    }
  });
}
