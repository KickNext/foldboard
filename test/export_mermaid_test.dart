import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/domain/use_cases/export_architecture_mermaid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const export = ExportArchitectureMermaid();

  test('processes become nested subgraphs and arrows become links', () {
    final mermaid = export(
      title: 'Board',
      revision: 4,
      nodes: const [
        ArchitectureNode(id: 'a', title: 'Reader'),
        ArchitectureNode(id: 'b', title: 'Writer', parentId: 'g'),
      ],
      groups: const [
        ArchitectureGroup(id: 'g', title: 'Storage'),
        ArchitectureGroup(id: 'h', title: 'Inner', parentId: 'g'),
      ],
      edges: const [
        ArchitectureEdge(id: 'e1', from: 'a', to: 'b'),
        ArchitectureEdge(id: 'e2', from: 'a', to: 'g'),
      ],
    );
    expect(mermaid, '''
%% Foldboard · Board · revision 4
flowchart LR
  N1["Reader"]
  subgraph P1["Storage"]
    direction LR
    N2["Writer"]
    subgraph P2["Inner"]
      direction LR
    end
  end
  N1 --> N2
  N1 --> P1
''');
  });

  test('labels stay inside quotes and mermaid entities are escaped', () {
    final mermaid = export(
      title: 'T',
      revision: 0,
      nodes: const [
        ArchitectureNode(id: 'a', title: 'Say "hi"\nand #go'),
        ArchitectureNode(id: 'b', title: '   '),
      ],
      groups: const [],
      edges: const [],
    );
    expect(mermaid, contains('N1["Say #quot;hi#quot; and #35;go"]'));
    expect(mermaid, contains('N2["—"]'));
  });

  test('an arrow to a missing endpoint is skipped, not emitted broken', () {
    final mermaid = export(
      title: 'T',
      revision: 0,
      nodes: const [ArchitectureNode(id: 'a', title: 'A')],
      groups: const [],
      edges: const [ArchitectureEdge(id: 'e', from: 'a', to: 'gone')],
    );
    expect(mermaid, isNot(contains('-->')));
  });
}
