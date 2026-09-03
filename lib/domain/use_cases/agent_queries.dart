import '../models/architecture_models.dart';

class AgentQueries {
  AgentQueries(this.nodes, this.groups, this.edges);
  final List<ArchitectureNode> nodes;
  final List<ArchitectureGroup> groups;
  final List<ArchitectureEdge> edges;

  List<Map<String, dynamic>> get _cards => [
    for (final n in nodes) {'type': 'node', ...n.toJson()},
    for (final g in groups) {'type': 'group', ...g.toJson()},
  ];

  Map<String, dynamic> _projectCard(
    Map<String, dynamic> row, {
    required bool coordinates,
    required int descriptionLimit,
  }) {
    final description = row['description'] as String;
    final title = row['title'] as String;
    return {
      'id': row['id'],
      'title': _clip(title, 160),
      if (title.length > 160) 'titleTruncated': true,
      'parentId': row['parentId'],
      if (descriptionLimit > 0)
        'description': _clip(description, descriptionLimit),
      if (description.length > descriptionLimit) 'descriptionTruncated': true,
      if (coordinates) ...{'x': row['x'], 'y': row['y']},
    };
  }

  // Avoid splitting a UTF-16 surrogate pair at the clipping boundary.
  String _clip(String text, int limit) {
    if (text.length <= limit) return text;
    var end = limit;
    if (end > 0 &&
        text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    return text.substring(0, end);
  }

  /// Bounded read projection, not an import document. Connections can reference
  /// IDs outside this page; callers resolve those IDs only when needed.
  Map<String, dynamic> readArea({
    String? id,
    int maxDepth = 1,
    int offset = 0,
    int limit = 20,
    int edgeOffset = 0,
    int edgeLimit = 20,
    int descriptionLimit = 500,
    bool coordinates = false,
  }) {
    final cards = _cards;
    final children = <String?, List<Map<String, dynamic>>>{};
    for (final card in cards) {
      children.putIfAbsent(card['parentId'] as String?, () => []).add(card);
    }
    final candidates = <Map<String, dynamic>>[];
    var depthTruncated = false;
    void visit(String? parent, int depth) {
      final nested = children[parent] ?? [];
      if (depth > maxDepth) {
        if (nested.isNotEmpty) depthTruncated = true;
        return;
      }
      for (final card in nested) {
        candidates.add(card);
        if (card['type'] == 'group') visit(card['id'] as String, depth + 1);
      }
    }

    if (id == null) {
      visit(null, 1);
    } else {
      final anchor = cards.firstWhere((row) => row['id'] == id);
      candidates.add(anchor);
      if (anchor['type'] == 'group') visit(id, 1);
    }
    final page = candidates.skip(offset).take(limit).toList();
    final ids = page.map((row) => row['id']).toSet();
    final connections = edges
        .where((e) => ids.contains(e.from) || ids.contains(e.to))
        .toList();
    return {
      'partial': true,
      'area': {
        'nodes': [
          for (final row in page.where((r) => r['type'] == 'node'))
            _projectCard(
              row,
              coordinates: coordinates,
              descriptionLimit: descriptionLimit,
            ),
        ],
        'groups': [
          for (final row in page.where((r) => r['type'] == 'group'))
            {
              ..._projectCard(
                row,
                coordinates: coordinates,
                descriptionLimit: descriptionLimit,
              ),
              'childCount': children[row['id']]?.length ?? 0,
            },
        ],
        'edges': connections
            .skip(edgeOffset)
            .take(edgeLimit)
            .map((e) => e.toJson())
            .toList(),
      },
      'total': candidates.length,
      'nextOffset': offset + limit < candidates.length ? offset + limit : null,
      'depthTruncated': depthTruncated,
      'totalEdges': connections.length,
      'nextEdgeOffset': edgeOffset + edgeLimit < connections.length
          ? edgeOffset + edgeLimit
          : null,
    };
  }

  Map<String, dynamic> search(String query, {int offset = 0, int limit = 20}) {
    final needle = query.trim().toLowerCase();
    final snippetMatch = RegExp(
      RegExp.escape(needle),
      caseSensitive: false,
      unicode: true,
    );
    final matches = _cards
        .where(
          (row) => '${row['title']} ${row['description']}'
              .toLowerCase()
              .contains(needle),
        )
        .toList();
    final parents = {for (final g in groups) g.id: g.parentId};
    return {
      'total': matches.length,
      'results': [
        for (final row in matches.skip(offset).take(limit))
          (() {
            final description = row['description'] as String;
            // Use original-string offsets: lowercasing can expand characters.
            final at = snippetMatch.firstMatch(description)?.start ?? 0;
            var start = at > 40 ? at - 40 : 0;
            if (start > 0 &&
                description.codeUnitAt(start) >= 0xdc00 &&
                description.codeUnitAt(start) <= 0xdfff) {
              start--;
            }
            final path = <String>[];
            var parent = row['parentId'] as String?;
            while (parent != null) {
              path.add(parent);
              parent = parents[parent];
            }
            return {
              'id': row['id'],
              'type': row['type'],
              'title': _clip(row['title'] as String, 160),
              if ((row['title'] as String).length > 160) 'titleTruncated': true,
              'parentId': row['parentId'],
              'pathIds': path.reversed.toList(),
              'snippet': _clip(description.substring(start), 160),
              'descriptionTruncated': start > 0 || description.length > 160,
            };
          })(),
      ],
      'nextOffset': offset + limit < matches.length ? offset + limit : null,
    };
  }

  Map<String, dynamic> outline({int maxDepth = 8}) {
    final children = <String?, List<ArchitectureGroup>>{};
    final counts = <String?, int>{};
    for (final g in groups) {
      children.putIfAbsent(g.parentId, () => []).add(g);
    }
    for (final n in nodes) {
      counts.update(n.parentId, (n) => n + 1, ifAbsent: () => 1);
    }
    Map<String, dynamic> level(String? id, String title, int depth) {
      final nested = children[id] ?? [];
      return {
        'id': id,
        'title': title,
        'blocks': counts[id] ?? 0,
        'processes': nested.length,
        if (depth < maxDepth)
          'children': [for (final g in nested) level(g.id, g.title, depth + 1)],
        if (depth >= maxDepth && nested.isNotEmpty) 'truncated': true,
      };
    }

    return {
      'totals': {
        'blocks': nodes.length,
        'processes': groups.length,
        'arrows': edges.length,
      },
      'outline': level(null, 'Board', 0),
    };
  }

  List<Map<String, dynamic>> validate({int maxDepth = 8}) {
    final issues = <Map<String, dynamic>>[];
    final parents = {
      for (final n in nodes) n.id: n.parentId,
      for (final g in groups) g.id: g.parentId,
    };
    final connected = <String>{};
    void touch(String id) {
      String? next = id;
      while (next != null && connected.add(next)) {
        next = parents[next];
      }
    }

    for (final e in edges) {
      touch(e.from);
      touch(e.to);
    }
    final names = <(String?, String), List<String>>{};
    for (final item in [
      ...nodes.map((n) => n.toJson()),
      ...groups.map((g) => g.toJson()),
    ]) {
      final id = item['id'] as String;
      final title = (item['title'] as String).trim();
      final description = (item['description'] as String).trim();
      void issue(String code) => issues.add({
        'code': code,
        'severity': 'warning',
        'ids': [id],
      });
      if (!connected.contains(id)) issue('unconnected-card');
      if (description.isEmpty) issue('empty-description');
      if (title.isEmpty) {
        issue('empty-title');
      } else {
        names
            .putIfAbsent((
              item['parentId'] as String?,
              title.toLowerCase(),
            ), () => [])
            .add(id);
      }
      var depth = 0;
      var parent = parents[id];
      while (parent != null && depth <= 128) {
        depth++;
        parent = parents[parent];
      }
      if (depth > maxDepth) issue('deep-nesting');
    }
    for (final ids in names.values.where((ids) => ids.length > 1)) {
      issues.add({
        'code': 'duplicate-title',
        'severity': 'warning',
        'ids': ids,
      });
    }
    return issues;
  }
}
