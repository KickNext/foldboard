import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/ui/features/planner/view_models/edge_routes.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Arrange keeps external inputs left, feedback intact and repeat stable',
    () {
      final repo = ArchitectureRepository()
        ..replace({
          'groups': [
            {'id': 'app', 'title': 'App'},
          ],
          'nodes': [
            for (final id in [
              'person',
              'agent',
              'editor',
              'bridge',
              'graph',
              'export',
            ])
              {
                'id': id,
                'title': id,
                'parentId': ['person', 'agent'].contains(id) ? null : 'app',
              },
          ],
          'edges': [
            for (final pair in [
              ('person', 'editor'),
              ('agent', 'bridge'),
              ('editor', 'graph'),
              ('bridge', 'graph'),
              ('graph', 'export'),
              ('export', 'agent'),
            ])
              {'id': '${pair.$1}-${pair.$2}', 'from': pair.$1, 'to': pair.$2},
          ],
        });
      final vm = PlannerViewModel(repository: repo, registerBridge: false)
        ..openLevel('app');
      addTearDown(vm.dispose);
      addTearDown(repo.dispose);
      final originalEdges = repo.edges.map((e) => e.toJson()).toList();
      final outside = repo.nodes
          .where((n) => n.parentId == null)
          .map((n) => n.toJson())
          .toList();
      vm.autoArrange();
      final positions = {for (final n in vm.canvasNodes) n.id: n.position};
      expect(positions['person']!.dx, positions['agent']!.dx);
      expect(positions['editor']!.dx, positions['bridge']!.dx);
      expect(positions['agent']!.dx, lessThan(positions['bridge']!.dx));
      expect(positions['bridge']!.dx, lessThan(positions['graph']!.dx));
      expect(positions['graph']!.dx, lessThan(positions['export']!.dx));
      expect(positions.values.map((p) => p.dx).toSet(), hasLength(4));
      final routes = EdgeRouter().route(vm.canvasNodes, vm.canvasEdges);
      final returnRoute = routes.firstWhere(
        (route) => route.edge.id == 'export-agent',
      );
      final exportBox = positions['export']! & EdgeRouter.cardSize;
      final agentBox = positions['agent']! & EdgeRouter.cardSize;
      expect(returnRoute.points.first.dx, exportBox.left);
      expect(returnRoute.tip.dx, agentBox.right);
      for (final route in routes) {
        for (final metric in route.path.computeMetrics()) {
          for (double d = 1; d < metric.length; d += 3) {
            final p = metric.getTangentForOffset(d)!.position;
            for (final n in vm.canvasNodes) {
              expect(
                (n.position & EdgeRouter.cardSize).deflate(.1).contains(p),
                isFalse,
                reason: '${route.edge.id} intersects ${n.id}',
              );
            }
          }
        }
      }
      final snapshot = vm.prettyJson;
      vm.autoArrange();
      expect({for (final n in vm.canvasNodes) n.id: n.position}, positions);
      expect(
        vm.prettyJson,
        snapshot,
        reason: 'No extra save for identical layout',
      );
      expect(repo.edges.map((e) => e.toJson()).toList(), originalEdges);
      expect(
        repo.nodes
            .where((n) => n.parentId == null)
            .map((n) => n.toJson())
            .toList(),
        outside,
      );
      vm.openLevel(null);
      vm.openLevel('app');
      expect({for (final n in vm.canvasNodes) n.id: n.position}, positions);
    },
  );
}
