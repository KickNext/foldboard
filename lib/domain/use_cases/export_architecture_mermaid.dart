import '../models/architecture_models.dart';

/// A Mermaid flowchart of the whole document: processes become nested
/// subgraphs, blocks become nodes, arrows become links.
///
/// Deterministic and coordinate-free, like the Markdown export. Identifiers
/// are the same `P`/`N` references, so the two documents can be read together.
class ExportArchitectureMermaid {
  const ExportArchitectureMermaid();

  String call({
    required String title,
    required int revision,
    required List<ArchitectureNode> nodes,
    required List<ArchitectureGroup> groups,
    required List<ArchitectureEdge> edges,
    String direction = 'LR',
  }) {
    final refs = <String, String>{
      for (var index = 0; index < groups.length; index++)
        groups[index].id: 'P${index + 1}',
      for (var index = 0; index < nodes.length; index++)
        nodes[index].id: 'N${index + 1}',
    };
    final buffer = StringBuffer()
      ..writeln('%% Foldboard · ${_comment(title)} · revision $revision')
      ..writeln('flowchart $direction');

    void writeLevel(String? parentId, int depth) {
      final pad = '  ' * (depth + 1);
      for (final node in nodes.where((n) => n.parentId == parentId)) {
        buffer.writeln('$pad${refs[node.id]}["${_label(node.title)}"]');
      }
      for (final group in groups.where((g) => g.parentId == parentId)) {
        buffer
          ..writeln(
            '${pad}subgraph ${refs[group.id]}["${_label(group.title)}"]',
          )
          ..writeln('$pad  direction $direction');
        writeLevel(group.id, depth + 1);
        buffer.writeln('${pad}end');
      }
    }

    writeLevel(null, 0);

    // Links come last so every endpoint is already declared inside its level.
    for (final edge in edges) {
      final from = refs[edge.from];
      final to = refs[edge.to];
      if (from == null || to == null) continue;
      buffer.writeln('  $from --> $to');
    }
    return buffer.toString();
  }

  /// Mermaid reads `#` as the start of an entity and `"` as the label end.
  String _label(String value) {
    final text = value
        .replaceAll('#', '#35;')
        .replaceAll('"', '#quot;')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();
    return text.isEmpty ? '—' : text;
  }

  String _comment(String value) =>
      value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
}
