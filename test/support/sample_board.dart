import 'dart:ui';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';

ArchitectureRepository sampleBoard() {
  final repo = ArchitectureRepository();
  repo.addGroup(
    const ArchitectureGroup(
      id: 'commerce-platform',
      title: 'Sample project',
      position: Offset(100, 100),
      size: Size(1600, 700),
    ),
  );
  repo.addGroup(
    const ArchitectureGroup(
      id: 'core-domain',
      title: 'Core',
      parentId: 'commerce-platform',
      position: Offset(400, 200),
      size: Size(800, 500),
    ),
  );
  repo.addNode(
    const ArchitectureNode(
      id: 'web-client',
      title: 'Web client',
      description: 'User interface',
      position: Offset(200, 200),
      parentId: 'commerce-platform',
    ),
  );
  repo.addNode(
    const ArchitectureNode(
      id: 'core-service',
      title: 'Order service',
      description: 'Handles orders',
      position: Offset(620, 340),
      parentId: 'core-domain',
    ),
  );
  repo.addNode(
    const ArchitectureNode(
      id: 'storage',
      title: 'Storage',
      position: Offset(1200, 400),
      parentId: 'commerce-platform',
    ),
  );
  repo.addEdge(
    const ArchitectureEdge(
      id: 'ui-core',
      from: 'web-client',
      to: 'core-service',
    ),
  );
  repo.addEdge(
    const ArchitectureEdge(
      id: 'core-storage',
      from: 'core-service',
      to: 'storage',
    ),
  );
  return repo;
}
