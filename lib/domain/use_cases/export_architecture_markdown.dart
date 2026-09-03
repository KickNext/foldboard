import '../models/architecture_models.dart';

/// Deterministic, coordinate-free process documentation for people and agents.
class ExportArchitectureMarkdown {
  const ExportArchitectureMarkdown();

  String call({
    required String title,
    required int revision,
    required List<ArchitectureNode> nodes,
    required List<ArchitectureGroup> groups,
    required List<ArchitectureEdge> edges,
    bool includeIds = false,
  }) {
    final buffer = StringBuffer();
    final nodeById = {for (final node in nodes) node.id: node};
    final groupById = {for (final group in groups) group.id: group};
    String name(String id) => nodeById[id]?.title ?? groupById[id]?.title ?? id;
    String kind(String id) => groupById.containsKey(id) ? 'process' : 'card';
    List<ArchitectureGroup> childGroups(String? parentId) =>
        groups.where((group) => group.parentId == parentId).toList();
    List<ArchitectureNode> childNodes(String? parentId) =>
        nodes.where((node) => node.parentId == parentId).toList();

    final refs = <String, String>{
      for (var index = 0; index < groups.length; index++)
        groups[index].id: 'P${index + 1}',
      for (var index = 0; index < nodes.length; index++)
        nodes[index].id: 'N${index + 1}',
      for (var index = 0; index < edges.length; index++)
        edges[index].id: 'C${index + 1}',
    };
    String ref(String id) => refs[id] ?? '?';

    buffer
      ..writeln('# ${_inline(title)}')
      ..writeln()
      ..writeln(
        '> Foldboard process document. Compact references connect the sections; '
        'canvas coordinates and UI state are intentionally omitted.',
      )
      ..writeln()
      ..writeln('- Revision: `$revision`')
      ..writeln('- Cards: `${nodes.length}`')
      ..writeln('- Processes: `${groups.length}`')
      ..writeln('- Connections: `${edges.length}`')
      ..writeln()
      ..writeln('## Process hierarchy')
      ..writeln();

    void writeTree(String? parentId, int depth) {
      for (final group in childGroups(parentId)) {
        buffer.writeln(
          '${'  ' * depth}- **${_inline(group.title)}** '
          '`${ref(group.id)}`',
        );
        writeTree(group.id, depth + 1);
      }
    }

    if (childGroups(null).isEmpty) {
      buffer.writeln('_No nested processes._');
    } else {
      writeTree(null, 0);
    }

    final orderedGroups = <ArchitectureGroup>[];
    void collectGroups(String? parentId) {
      for (final group in childGroups(parentId)) {
        orderedGroups.add(group);
        collectGroups(group.id);
      }
    }

    collectGroups(null);

    void writeLevel({
      required String heading,
      required String path,
      required String? parentId,
      String description = '',
      String? id,
    }) {
      buffer
        ..writeln()
        ..writeln('## ${_inline(heading)}')
        ..writeln()
        ..writeln('- Path: `${_codeText(path)}`');
      if (id != null) buffer.writeln('- Process ID: ${_code(id)}');
      if (description.trim().isNotEmpty) {
        buffer
          ..writeln()
          ..writeln(_quote(description));
      }

      final directNodes = childNodes(parentId);
      buffer
        ..writeln()
        ..writeln('### Direct cards')
        ..writeln();
      if (directNodes.isEmpty) {
        buffer.writeln('_None._');
      } else {
        for (final node in directNodes) {
          buffer.writeln('- `${ref(node.id)}` **${_inline(node.title)}**');
          if (node.description.trim().isNotEmpty) {
            buffer.writeln('  ${_listText(node.description)}');
          }
        }
      }

      final directGroups = childGroups(parentId);
      buffer
        ..writeln()
        ..writeln('### Child processes')
        ..writeln();
      if (directGroups.isEmpty) {
        buffer.writeln('_None._');
      } else {
        for (final group in directGroups) {
          buffer.writeln('- `${ref(group.id)}` **${_inline(group.title)}**');
        }
      }
    }

    writeLevel(heading: 'Root level', path: '/', parentId: null);
    for (final group in orderedGroups) {
      final path = <String>[group.title];
      var parent = group.parentId;
      while (parent != null) {
        final ancestor = groupById[parent];
        if (ancestor == null) break;
        path.insert(0, ancestor.title);
        parent = ancestor.parentId;
      }
      writeLevel(
        heading: '${ref(group.id)} · Process: ${group.title}',
        path: '/${path.join('/')}',
        parentId: group.id,
        description: group.description,
        id: includeIds ? group.id : null,
      );
    }

    final incoming = {
      for (final id in [...nodeById.keys, ...groupById.keys]) id: 0,
    };
    final outgoing = {for (final id in incoming.keys) id: 0};
    for (final edge in edges) {
      if (outgoing.containsKey(edge.from)) {
        outgoing[edge.from] = outgoing[edge.from]! + 1;
      }
      if (incoming.containsKey(edge.to)) {
        incoming[edge.to] = incoming[edge.to]! + 1;
      }
    }
    final entries = incoming.keys
        .where((id) => incoming[id] == 0 && outgoing[id]! > 0)
        .toList();
    final exits = outgoing.keys
        .where((id) => outgoing[id] == 0 && incoming[id]! > 0)
        .toList();
    final unconnected = incoming.keys
        .where((id) => incoming[id] == 0 && outgoing[id] == 0)
        .toList();

    void writeRefs(String label, List<String> ids) {
      buffer.write('- $label: ');
      if (ids.isEmpty) {
        buffer.writeln('_None_');
      } else {
        buffer.writeln(
          ids
              .map(
                (id) => '`${ref(id)}` **${_inline(name(id))}** (${kind(id)})',
              )
              .join('; '),
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('## Flow boundaries')
      ..writeln();
    writeRefs('Entry points', entries);
    writeRefs('Exit points', exits);
    writeRefs('Unconnected', unconnected);

    buffer
      ..writeln()
      ..writeln('## Connections')
      ..writeln();
    if (edges.isEmpty) {
      buffer.writeln('_None._');
    } else {
      for (var index = 0; index < edges.length; index++) {
        final edge = edges[index];
        buffer.writeln(
          '${index + 1}. `${ref(edge.id)}` '
          '`${ref(edge.from)}` **${_inline(name(edge.from))}** → '
          '`${ref(edge.to)}` **${_inline(name(edge.to))}**',
        );
      }
    }

    if (includeIds) {
      buffer
        ..writeln()
        ..writeln('## WebMCP ID index')
        ..writeln()
        ..writeln(
          '_Use these stable IDs only when applying changes back to Foldboard._',
        )
        ..writeln();
      for (final group in groups) {
        buffer.writeln('- `${ref(group.id)}` → ${_code(group.id)} (process)');
      }
      for (final node in nodes) {
        buffer.writeln('- `${ref(node.id)}` → ${_code(node.id)} (card)');
      }
      for (final edge in edges) {
        buffer.writeln('- `${ref(edge.id)}` → ${_code(edge.id)} (connection)');
      }
    }
    return '${buffer.toString().trimRight()}\n';
  }

  String _inline(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('*', '\\*')
      .replaceAll('_', '\\_')
      .replaceAll('[', '\\[')
      .replaceAll(']', '\\]')
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .trim();

  String _code(String value) => '`${_codeText(value)}`';
  String _codeText(String value) => value.replaceAll('`', 'ˋ');
  String _quote(String value) => value
      .trim()
      .split(RegExp(r'\r?\n'))
      .map((line) => '> ${line.trim()}')
      .join('\n');
  String _listText(String value) => value
      .trim()
      .replaceAll(RegExp(r'[\r\n]+'), '<br>')
      .replaceAll('|', '\\|');
}
