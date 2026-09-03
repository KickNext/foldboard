import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../domain/models/architecture_models.dart';
import '../../domain/models/agent_protocol.dart';
import 'board_store.dart';

enum StorageFailure { read, write, conflict }

class AncestorConnectionException extends FormatException {
  const AncestorConnectionException()
    : super(
        'An arrow cannot connect a card to its containing process or any ancestor, in either direction.',
      );
}

/// Session-only history. It is restored only for the exact saved document.
class BoardHistory {
  BoardHistory._(this.document, this.undo, this.redo);
  final String document;
  final List<Map<String, dynamic>> undo;
  final List<Map<String, dynamic>> redo;
}

typedef _BoardState = ({
  List<ArchitectureNode> nodes,
  List<ArchitectureGroup> groups,
  List<ArchitectureEdge> edges,
  Map<String, Map<String, Offset>> references,
});

class ArchitectureRepository extends ChangeNotifier {
  ArchitectureRepository({BoardStore? store, this.readOnly = false})
    : _store = store == null ? null : CheckedBoardStore(store) {
    try {
      final saved = _store?.read();
      if (saved != null) {
        _load(Map<String, dynamic>.from(jsonDecode(saved) as Map));
        revision = (jsonDecode(saved)['revision'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {
      storageError = StorageFailure.read;
      _loadFailed = true;
    }
  }
  final CheckedBoardStore? _store;
  final bool readOnly;
  bool get canEdit =>
      !readOnly && !_loadFailed && storageError != StorageFailure.conflict;
  final List<Map<String, dynamic>> _undo = [];
  final List<Map<String, dynamic>> _redo = [];
  Map<String, dynamic>? _transactionStart;
  bool get transactionActive => _transactionStart != null;
  String? _historyKey;
  DateTime? _historyTime;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  BoardHistory saveHistory() {
    endTransaction();
    return BoardHistory._(
      jsonEncode(snapshot()),
      List.of(_undo),
      List.of(_redo),
    );
  }

  void restoreHistory(BoardHistory history) {
    if (history.document != jsonEncode(snapshot())) return;
    _undo.addAll(history.undo);
    _redo.addAll(history.redo);
  }

  void beginTransaction() {
    _transactionStart ??= snapshot();
    _historyKey = null;
  }

  void endTransaction() {
    final before = _transactionStart;
    _transactionStart = null;
    if (before != null && before['revision'] != revision) {
      _remember(before);
      notifyListeners();
    }
  }

  void _remember(Map<String, dynamic> before, {String? historyKey}) {
    if (_transactionStart != null) return;
    final now = DateTime.now();
    final merge =
        historyKey != null &&
        historyKey == _historyKey &&
        _historyTime != null &&
        now.difference(_historyTime!).inMilliseconds < 700;
    if (!merge) {
      _undo.add(before);
      if (_undo.length > 100) _undo.removeAt(0);
    }
    _redo.clear();
    _historyKey = historyKey;
    _historyTime = now;
  }

  void undo() => _restoreHistory(_undo, _redo);
  void redo() => _restoreHistory(_redo, _undo);
  void _restoreHistory(
    List<Map<String, dynamic>> from,
    List<Map<String, dynamic>> to,
  ) {
    endTransaction();
    if (from.isEmpty) return;
    _checkRevision(null);
    final before = snapshot();
    to.add(before);
    _load(from.removeLast());
    _historyKey = null;
    _changed(before: before);
  }

  Timer? _saveTimer;
  bool _loadFailed = false;
  StorageFailure? storageError;
  bool pendingSave = false;
  int revision = 0;
  static int _nextHistory = 0;
  final String historyId =
      '${DateTime.now().microsecondsSinceEpoch}-${_nextHistory++}';
  final List<Map<String, dynamic>> _changeLog = [];
  int _changeLogBytes = 0;
  Map<String, dynamic> changesSince(
    int since, {
    String? history,
    bool events = false,
  }) {
    if (history != null && history != historyId) {
      throw const AgentException(
        'history-expired',
        'Change history belongs to another session. Read the outline/area again.',
      );
    }
    if (since > revision || since < 0) {
      throw const AgentException(
        'revision-conflict',
        'Requested revision is not available.',
      );
    }
    final oldest = _changeLog.isEmpty
        ? revision
        : (_changeLog.first['revision'] as int) - 1;
    if (since < oldest) {
      throw const AgentException(
        'history-expired',
        'Change history expired. Read the outline/area again.',
      );
    }
    final entries = _changeLog
        .where((entry) => (entry['revision'] as int) > since)
        .toList();
    return {
      'sinceRevision': since,
      'revision': revision,
      'historyId': historyId,
      'mode': events ? 'events' : 'compact',
      if (events)
        'changes': entries
      else
        'patch': composePatches(
          entries.map(
            (entry) => Map<String, dynamic>.from(entry['patch'] as Map),
          ),
        ),
    };
  }

  List<ArchitectureNode> _nodes = [];
  List<ArchitectureGroup> _groups = [];
  List<ArchitectureEdge> _edges = [];
  Map<String, Map<String, Offset>> _referencePositions = {};
  Map<String, Offset> referencePositions(String? level) =>
      Map.unmodifiable(_referencePositions[level ?? ''] ?? const {});
  List<ArchitectureNode> get nodes => List.unmodifiable(_nodes);
  List<ArchitectureGroup> get groups => List.unmodifiable(_groups);
  List<ArchitectureEdge> get edges => List.unmodifiable(_edges);

  Map<String, String?> get _parents => {
    for (final n in _nodes) n.id: n.parentId,
    for (final g in _groups) g.id: g.parentId,
  };

  static bool _connectsAncestor(
    String from,
    String to,
    Map<String, String?> parents,
  ) {
    bool contains(String container, String child) {
      final visited = <String>{};
      var parent = parents[child];
      while (parent != null && visited.add(parent)) {
        if (parent == container) return true;
        parent = parents[parent];
      }
      return false;
    }

    return contains(from, to) || contains(to, from);
  }

  bool connectsAncestor(String from, String to) =>
      _connectsAncestor(from, to, _parents);

  Map<String, dynamic> snapshot() => _stateJson((
    nodes: _nodes,
    groups: _groups,
    edges: _edges,
    references: _referencePositions,
  ));

  Map<String, dynamic> _stateJson(_BoardState state) => {
    'revision': revision,
    'nodes': state.nodes.map((n) => n.toJson()).toList(),
    'groups': state.groups.map((g) => g.toJson()).toList(),
    'edges': state.edges.map((e) => e.toJson()).toList(),
    if (state.references.isNotEmpty)
      'referencePositions': {
        for (final level in state.references.entries)
          level.key: {
            for (final p in level.value.entries)
              p.key: {'x': p.value.dx, 'y': p.value.dy},
          },
      },
  };

  _BoardState _load(Map<String, dynamic> source, {bool commit = true}) {
    final json = source;
    List<Map<String, dynamic>> rows(String key) => (json[key] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final nodes = rows('nodes').map(ArchitectureNode.fromJson).toList();
    final groups = rows('groups').map(ArchitectureGroup.fromJson).toList();
    final edges = rows('edges').map(ArchitectureEdge.fromJson).toList();
    final ids = <String>{};
    for (final id in [
      ...nodes.map((n) => n.id),
      ...groups.map((g) => g.id),
      ...edges.map((e) => e.id),
    ]) {
      if (id.trim().isEmpty || !ids.add(id)) {
        throw FormatException('Empty or duplicate id: $id');
      }
    }
    final groupMap = {for (final g in groups) g.id: g};
    for (final group in groups) {
      if (group.size.width < 80 || group.size.height < 80) {
        throw const FormatException('Area is too small');
      }
      final visited = <String>{group.id};
      var parent = group.parentId;
      while (parent != null) {
        if (!groupMap.containsKey(parent)) {
          throw AgentException('unknown-id', 'Unknown parent: $parent');
        }
        if (!visited.add(parent) || visited.length > 128) {
          throw const FormatException('Invalid area nesting');
        }
        parent = groupMap[parent]!.parentId;
      }
    }
    for (final node in nodes) {
      if (node.parentId != null && !groupMap.containsKey(node.parentId)) {
        throw const AgentException('unknown-id', 'Unknown node area');
      }
    }
    final nodeIds = {...nodes.map((n) => n.id), ...groupMap.keys};
    final parents = {
      for (final n in nodes) n.id: n.parentId,
      for (final g in groups) g.id: g.parentId,
    };
    final pairs = <(String, String)>{};
    for (final edge in edges) {
      if (!nodeIds.contains(edge.from) || !nodeIds.contains(edge.to)) {
        throw const AgentException(
          'unknown-id',
          'Arrow endpoint does not exist.',
        );
      }
      if (!nodeIds.contains(edge.from) ||
          !nodeIds.contains(edge.to) ||
          edge.from == edge.to ||
          !pairs.add((edge.from, edge.to))) {
        throw const FormatException('Invalid or duplicate arrow');
      }
      if (_connectsAncestor(edge.from, edge.to, parents)) {
        throw const AncestorConnectionException();
      }
    }
    final references = <String, Map<String, Offset>>{};
    for (final level in (json['referencePositions'] as Map? ?? {}).entries) {
      final key = level.key as String;
      if (key.isNotEmpty && !groupMap.containsKey(key)) continue;
      references[key] = {
        for (final point in (level.value as Map).entries)
          if (nodeIds.contains(point.key))
            point.key as String: Offset(
              numberValue(
                Map<String, dynamic>.from(point.value as Map),
                'x',
                0,
              ),
              numberValue(
                Map<String, dynamic>.from(point.value as Map),
                'y',
                0,
              ),
            ),
      };
    }
    // Commit only after the entire candidate document passes validation.
    if (commit) {
      _nodes = nodes;
      _groups = groups;
      _edges = edges;
      _referencePositions = references;
    }
    return (nodes: nodes, groups: groups, edges: edges, references: references);
  }

  void replace(Map<String, dynamic> document, {int? expectedRevision}) {
    _checkRevision(expectedRevision);
    final before = snapshot();
    _load(document);
    _remember(before);
    _changed(before: before);
  }

  void applyChanges(
    Map<String, dynamic> changes, {
    int? expectedRevision,
    String? historyKey,
  }) {
    _checkRevision(expectedRevision);
    final before = snapshot();
    final candidate = _changeCandidate(changes);
    _load(candidate);
    _remember(before, historyKey: historyKey);
    _changed(before: before);
  }

  /// Uses the same candidate builder and validator as a real write. No store,
  /// history, timers, notifications, selection or revision are touched.
  Map<String, dynamic> previewChanges(
    Map<String, dynamic> changes, {
    int? expectedRevision,
    bool replace = false,
  }) {
    if (_loadFailed) {
      throw const AgentException(
        'storage-error',
        'Saved board could not be loaded.',
      );
    }
    if (expectedRevision != null && expectedRevision != revision) {
      throw const AgentException(
        'revision-conflict',
        'Board changed; read it again before editing.',
      );
    }
    final state = _load(
      replace ? changes : _changeCandidate(changes),
      commit: false,
    );
    return _stateJson(state);
  }

  Map<String, dynamic> _changeCandidate(Map<String, dynamic> changes) {
    final candidate = snapshot();
    const collections = ['nodes', 'groups', 'edges'];
    for (final key in changes.keys) {
      if (!collections.contains(key) &&
          key != 'deleteIds' &&
          key != 'referencePositions' &&
          key != 'revision') {
        throw FormatException('Unknown change: $key');
      }
    }
    // Full board reads include revision. Accept it in a sparse batch so an
    // agent can pass a document through, but never let it bypass
    // expectedRevision.
    final sourceRevision = changes['revision'];
    if (sourceRevision != null &&
        (sourceRevision is! int || sourceRevision < 0)) {
      throw const FormatException('Invalid board revision');
    }
    if (changes.containsKey('referencePositions')) {
      candidate['referencePositions'] = changes['referencePositions'];
    }
    for (final key in collections) {
      final items = {
        for (final item
            in (candidate[key] as List).cast<Map<String, dynamic>>())
          item['id'] as String: item,
      };
      final batchIds = <String>{};
      for (final raw in (changes[key] as List? ?? [])) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item.containsKey('dataModelIds')) {
          throw const FormatException('Data models are no longer supported');
        }
        final id = item['id'] as String;
        if (!batchIds.add(id)) {
          throw const FormatException('Duplicate id in batch');
        }
        items[id] = {...?items[id], ...item};
      }
      candidate[key] = items.values.toList();
    }
    final deleted = ((changes['deleteIds'] as List?) ?? [])
        .cast<String>()
        .toSet();
    final all = [
      for (final key in collections) ...(candidate[key] as List).cast<Map>(),
    ];
    if (deleted.any((id) => !all.any((item) => item['id'] == id))) {
      throw const AgentException('unknown-id', 'Unknown deletion target');
    }
    final groupMap = {
      for (final g in (candidate['groups'] as List).cast<Map>()) g['id']: g,
    };
    String? survivingParent(String? id) {
      final visited = <String>{};
      while (id != null && deleted.contains(id)) {
        if (!visited.add(id)) {
          throw const FormatException('Invalid area nesting');
        }
        id = groupMap[id]?['parentId'] as String?;
      }
      return id;
    }

    final promoted = <Map<String, dynamic>>[];
    for (final key in collections) {
      candidate[key] = (candidate[key] as List)
          .cast<Map<String, dynamic>>()
          .where((item) => !deleted.contains(item['id']))
          .map((item) {
            if (key == 'nodes' || key == 'groups') {
              final parent = item['parentId'] as String?;
              item['parentId'] = survivingParent(parent);
              if (item['parentId'] != parent) promoted.add(item);
            }
            return item;
          })
          .where(
            (item) =>
                key != 'edges' ||
                (!deleted.contains(item['from']) &&
                    !deleted.contains(item['to'])),
          )
          .toList();
    }
    // Place promoted cards in free space, keeping existing siblings untouched.
    // Children of a promoted process keep their own independent level layout.
    if (promoted.isNotEmpty) {
      final occupied = <String?, List<Rect>>{};
      Rect cardRect(Map item) => Rect.fromLTWH(
        numberValue(Map<String, dynamic>.from(item), 'x', 400),
        numberValue(Map<String, dynamic>.from(item), 'y', 300),
        260,
        118,
      );
      final promotedIds = promoted.map((item) => item['id']).toSet();
      for (final item in [
        ...(candidate['nodes'] as List),
        ...(candidate['groups'] as List),
      ].cast<Map>()) {
        if (!promotedIds.contains(item['id'])) {
          occupied
              .putIfAbsent(item['parentId'] as String?, () => [])
              .add(cardRect(item));
        }
      }
      for (final item in promoted) {
        final siblings = occupied.putIfAbsent(
          item['parentId'] as String?,
          () => [],
        );
        var rect = cardRect(item);
        while (true) {
          final collisions = siblings
              .where((other) => other.inflate(24).overlaps(rect))
              .toList();
          if (collisions.isEmpty) break;
          final bottom = collisions
              .map((r) => r.bottom)
              .reduce((a, b) => a > b ? a : b);
          rect = Rect.fromLTWH(rect.left, bottom + 24, rect.width, rect.height);
        }
        item['x'] = rect.left;
        item['y'] = rect.top;
        siblings.add(rect);
      }
    }
    // Old saved arrows remain removable/editable; no new invalid relation may
    // enter through a batch, even when only parentId was changed.
    return candidate;
  }

  void _checkRevision(int? expected) {
    if (readOnly) throw const StorageConflict();
    if (_loadFailed) throw StateError('Saved board could not be loaded');
    if (storageError == StorageFailure.conflict) throw const StorageConflict();
    try {
      _store?.checkWrite();
    } on StorageConflict {
      storageError = StorageFailure.conflict;
      notifyListeners();
      rethrow;
    }
    if (expected != null && expected != revision) {
      throw const AgentException(
        'revision-conflict',
        'Board changed; read it again before editing',
      );
    }
  }

  void _changed({
    required Map<String, dynamic> before,
    Map<String, dynamic>? patch,
  }) {
    revision++;
    final entry = {
      'revision': revision,
      'patch': patch ?? documentDiff(before, snapshot()),
    };
    _changeLog.add(entry);
    _changeLogBytes += jsonEncode(entry).length;
    while (_changeLog.length > 128 ||
        (_changeLogBytes > 1000000 && _changeLog.isNotEmpty)) {
      _changeLogBytes -= jsonEncode(_changeLog.removeAt(0)).length;
    }
    if (_store != null) {
      pendingSave = true;
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 180), flush);
    }
    notifyListeners();
  }

  void flush() {
    _saveTimer?.cancel();
    if (_store == null || !pendingSave || _loadFailed) return;
    try {
      _store.write(jsonEncode(snapshot()));
      pendingSave = false;
      storageError = null;
    } on StorageConflict {
      storageError = StorageFailure.conflict;
    } catch (_) {
      storageError = StorageFailure.write;
    }
    notifyListeners();
  }

  void setNodePosition(String id, Offset position) {
    _checkRevision(null);
    if (!position.dx.isFinite || !position.dy.isFinite) {
      throw const FormatException('Invalid position');
    }
    final index = _nodes.indexWhere((n) => n.id == id);
    if (index < 0) return;
    if (_nodes[index].position == position) return;
    final previousPosition = _nodes[index].position;
    final before = snapshot();
    _remember(before);
    _nodes[index] = _nodes[index].copyWith(position: position);
    // Pointer moves already know their exact delta. Avoid scanning the whole
    // document again for the change journal on every drag frame.
    _changed(
      before: before,
      patch: {
        'nodes': [
          {
            'id': id,
            if (previousPosition.dx != position.dx) 'x': position.dx,
            if (previousPosition.dy != position.dy) 'y': position.dy,
          },
        ],
      },
    );
  }

  void addNode(ArchitectureNode node) => applyChanges({
    'nodes': [node.toJson()],
  });
  void addGroup(ArchitectureGroup group) => applyChanges({
    'groups': [group.toJson()],
  });
  bool addEdge(ArchitectureEdge edge) {
    try {
      applyChanges({
        'edges': [edge.toJson()],
      });
      return true;
    } on FormatException {
      return false;
    }
  }

  void clear() => replace({});
  void applyLayout({
    required Map<String, Offset> nodePositions,
    required Map<String, Rect> groupFrames,
  }) => applyChanges({
    'nodes': [
      for (final n in _nodes)
        if (nodePositions[n.id] case final Offset p)
          {'id': n.id, 'x': p.dx, 'y': p.dy},
    ],
    'groups': [
      for (final g in _groups)
        if (groupFrames[g.id] case final Rect r)
          {
            'id': g.id,
            'x': r.left,
            'y': r.top,
            'width': r.width,
            'height': r.height,
          },
    ],
  });
  @override
  void dispose() {
    flush();
    _saveTimer?.cancel();
    super.dispose();
  }
}
