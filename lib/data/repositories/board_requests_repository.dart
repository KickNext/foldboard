import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/models/agent_protocol.dart';
import '../../domain/models/board_request.dart';
import 'board_store.dart';

/// A separate per-project channel: board Undo/import must never erase a human
/// question or reopen an already handled request. Writes are synchronous and
/// publish only after persistence succeeds.
class BoardRequestsRepository extends ChangeNotifier {
  BoardRequestsRepository({BoardStore? store, this.readOnly = false})
    : _store = store == null ? null : CheckedBoardStore(store) {
    try {
      final raw = _store?.read();
      if (raw != null) {
        final json = jsonDecode(raw) as Map;
        final items = (json['requests'] as List)
            .map(
              (e) => BoardRequest.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        if (items.map((e) => e.id).toSet().length != items.length) {
          throw const FormatException('Duplicate request');
        }
        _items = items;
        revision = json['revision'] as int;
      }
    } catch (_) {
      loadFailed = true;
    }
  }
  final CheckedBoardStore? _store;
  final bool readOnly;
  bool loadFailed = false;
  bool conflict = false;
  bool _disposed = false;
  int revision = 0;
  final _random = Random.secure();
  List<BoardRequest> _items = [];
  List<BoardRequest> get items => List.unmodifiable(_items);
  bool get canEdit => !_disposed && !readOnly && !loadFailed && !conflict;
  int get pendingCount => _items.where((e) => e.status == 'pending').length;

  void _commit(List<BoardRequest> next) {
    if (_disposed) {
      throw const AgentException(
        'project-conflict',
        'The project was closed. Reopen it before saving the request.',
      );
    }
    if (loadFailed) {
      throw const AgentException(
        'storage-error',
        'Saved requests could not be loaded.',
      );
    }
    if (conflict) {
      throw const AgentException(
        'storage-conflict',
        'Requests changed in another session. Reload before editing.',
      );
    }
    if (readOnly) {
      throw const AgentException(
        'read-only',
        'Requests are read-only in this session.',
      );
    }
    try {
      _store?.write(
        jsonEncode({
          'revision': revision + 1,
          'requests': next.map((e) => e.toJson()).toList(),
        }),
      );
    } on StorageConflict {
      conflict = true;
      notifyListeners();
      throw const AgentException(
        'storage-conflict',
        'Requests changed in another session. Reload before editing.',
      );
    } catch (_) {
      throw const AgentException(
        'storage-error',
        'Request could not be saved. Retry or export your work.',
      );
    }
    _items = next;
    revision++;
    notifyListeners();
  }

  BoardRequest add(String text, Map<String, dynamic> context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 4000) {
      throw const AgentException(
        'invalid-arguments',
        'Request must contain 1–4000 characters.',
      );
    }
    final item = BoardRequest(
      id: 'r-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x100000000).toRadixString(16)}',
      text: trimmed,
      context: context,
      createdAt: DateTime.now().toUtc(),
    );
    _commit([..._items, item]);
    return item;
  }

  BoardRequest get(String id) =>
      _items.where((e) => e.id == id).firstOrNull ??
      (throw const AgentException('unknown-id', 'Request not found.'));
  BoardRequest resolve(
    String id, {
    required int expectedVersion,
    String? response,
  }) {
    final item = get(id);
    if (item.version != expectedVersion) {
      throw const AgentException(
        'request-conflict',
        'Request changed; read it again before marking it handled.',
      );
    }
    if ((response?.length ?? 0) > 4000) {
      throw const AgentException(
        'invalid-arguments',
        'Response must not exceed 4000 characters.',
      );
    }
    if (item.status == 'handled') return item;
    final next = item.handled(
      response?.trim().isEmpty == true ? null : response?.trim(),
    );
    _commit([for (final old in _items) old.id == id ? next : old]);
    return next;
  }

  void reopen(String id) {
    final item = get(id);
    if (item.status == 'pending') return;
    _commit([for (final old in _items) old.id == id ? item.reopen() : old]);
  }

  void remove(String id) {
    get(id);
    _commit(_items.where((e) => e.id != id).toList());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
