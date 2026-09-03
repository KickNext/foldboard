import 'dart:convert';

class AgentException extends FormatException {
  const AgentException(this.code, String message) : super(message);
  final String code;
}

/// Sparse forward patch. Consumers remove deleteIds before merging row fields,
/// without cascading: deleted edges and reparented children are already explicit.
Map<String, dynamic> documentDiff(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  final patch = <String, dynamic>{};
  final deleted = <String>[];
  for (final key in ['nodes', 'groups', 'edges']) {
    final old = {
      for (final row in (before[key] as List? ?? []))
        row['id'] as String: row as Map,
    };
    final next = {
      for (final row in (after[key] as List? ?? []))
        row['id'] as String: row as Map,
    };
    final updates = <Map<String, dynamic>>[];
    for (final entry in next.entries) {
      final previous = old[entry.key];
      final changed = <String, dynamic>{'id': entry.key};
      for (final field in entry.value.entries) {
        // Node/group/edge fields are scalars. Do not serialize every description
        // on each pointer move just to compare two strings.
        if (previous == null || previous[field.key] != field.value) {
          changed[field.key as String] = field.value;
        }
      }
      if (previous == null || changed.length > 1) updates.add(changed);
    }
    if (updates.isNotEmpty) patch[key] = updates;
    deleted.addAll(old.keys.where((id) => !next.containsKey(id)));
  }
  if (deleted.isNotEmpty) patch['deleteIds'] = deleted;
  if (jsonEncode(before['referencePositions']) !=
      jsonEncode(after['referencePositions'])) {
    patch['referencePositions'] =
        after['referencePositions'] ?? <String, dynamic>{};
  }
  return patch;
}

List<String> affectedIds(
  Map<String, dynamic> patch, {
  Map<String, dynamic>? before,
}) {
  final ids = {
    for (final key in ['nodes', 'groups', 'edges'])
      for (final row in (patch[key] as List? ?? [])) row['id'] as String,
    ...(patch['deleteIds'] as List? ?? []).cast<String>(),
  };
  if (patch.containsKey('referencePositions')) {
    final previous = before?['referencePositions'] as Map? ?? {};
    final next = patch['referencePositions'] as Map;
    for (final level in {...previous.keys, ...next.keys}) {
      final oldPositions = previous[level] as Map? ?? {};
      final newPositions = next[level] as Map? ?? {};
      for (final id in {...oldPositions.keys, ...newPositions.keys}) {
        if (jsonEncode(oldPositions[id]) != jsonEncode(newPositions[id])) {
          ids.add(id as String);
        }
      }
    }
  }
  return ids.toList()..sort();
}

/// Compose forward patches, preserving delete-before-upsert semantics even
/// when an ID is deleted, recreated or changes its collection within the range.
Map<String, dynamic> composePatches(Iterable<Map<String, dynamic>> patches) {
  const collections = ['nodes', 'groups', 'edges'];
  final rows = {
    for (final key in collections) key: <String, Map<String, dynamic>>{},
  };
  final deleted = <String>{};
  Map<String, dynamic>? references;
  for (final patch in patches) {
    for (final id in (patch['deleteIds'] as List? ?? []).cast<String>()) {
      deleted.add(id);
      for (final table in rows.values) {
        table.remove(id);
      }
    }
    for (final key in collections) {
      for (final row in patch[key] as List? ?? []) {
        final value = Map<String, dynamic>.from(row as Map);
        final id = value['id'] as String;
        rows[key]!.putIfAbsent(id, () => {}).addAll(value);
      }
    }
    if (patch.containsKey('referencePositions')) {
      references = Map<String, dynamic>.from(
        patch['referencePositions'] as Map,
      );
    }
  }
  return {
    if (deleted.isNotEmpty) 'deleteIds': deleted.toList(),
    for (final key in collections)
      if (rows[key]!.isNotEmpty) key: rows[key]!.values.toList(),
    'referencePositions': ?references,
  };
}

Map<String, dynamic> agentFailure(Object error, int? revision) => {
  'ok': false,
  'code': error is AgentException
      ? error.code
      : error is FormatException || error is TypeError || error is ArgumentError
      ? 'invalid-arguments'
      : 'internal-error',
  'error': error is AgentException
      ? error.message
      : error is FormatException
      ? error.message
      : 'The operation could not be completed.',
  'revision': ?revision,
};

Map<String, dynamic> changeCounts(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
  Map<String, dynamic> patch,
) {
  final result = <String, dynamic>{};
  for (final key in ['nodes', 'groups', 'edges']) {
    final oldIds = {for (final row in before[key] as List) row['id']};
    final newIds = {for (final row in after[key] as List) row['id']};
    result[key] = {
      'created': newIds.difference(oldIds).length,
      'updated': (patch[key] as List? ?? [])
          .where((row) => oldIds.contains(row['id']))
          .length,
      'deleted': oldIds.difference(newIds).length,
    };
  }
  return result;
}
