import 'dart:ui';

import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/domain/use_cases/export_architecture_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const exporter = ExportArchitectureMarkdown();
  const nodes = [
    ArchitectureNode(
      id: 'node-start-long-id',
      title: 'User request',
      description: 'A person describes the desired result.',
      position: Offset(120, 240),
    ),
    ArchitectureNode(
      id: 'node-agent-long-id',
      title: 'Agent action',
      description: 'The agent performs the task.',
      position: Offset(900, 480),
      parentId: 'process-work-long-id',
    ),
    ArchitectureNode(
      id: 'node-result-long-id',
      title: 'Result',
      position: Offset(1600, 720),
    ),
  ];
  const groups = [
    ArchitectureGroup(
      id: 'process-work-long-id',
      title: 'Work loop',
      description: 'The repeatable inner process.',
      position: Offset(500, 320),
      size: Size(760, 480),
    ),
  ];
  const edges = [
    ArchitectureEdge(
      id: 'connection-input-long-id',
      from: 'node-start-long-id',
      to: 'process-work-long-id',
    ),
    ArchitectureEdge(
      id: 'connection-output-long-id',
      from: 'process-work-long-id',
      to: 'node-result-long-id',
    ),
  ];

  test('exports a compact coordinate-free process document', () {
    final markdown = exporter(
      title: 'AI *process*',
      revision: 7,
      nodes: nodes,
      groups: groups,
      edges: edges,
    );

    expect(markdown, contains('# AI \\*process\\*'));
    expect(markdown, contains('`P1` **Work loop**'));
    expect(markdown, contains('`N2` **Agent action**'));
    expect(
      markdown,
      contains('`C1` `N1` **User request** → `P1` **Work loop**'),
    );
    expect(markdown, contains('Entry points'));
    expect(markdown, contains('Exit points'));
    expect(markdown, isNot(contains('node-start-long-id')));
    expect(markdown, isNot(contains('120')));
    expect(markdown, isNot(contains('referencePositions')));
  });

  test('adds stable IDs once when WebMCP editing needs them', () {
    final markdown = exporter(
      title: 'Agent process',
      revision: 7,
      nodes: nodes,
      groups: groups,
      edges: edges,
      includeIds: true,
    );

    expect(markdown, contains('## WebMCP ID index'));
    expect('node-start-long-id'.allMatches(markdown), hasLength(1));
    expect('connection-input-long-id'.allMatches(markdown), hasLength(1));
  });
}
