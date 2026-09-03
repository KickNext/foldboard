import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../domain/models/project.dart';
import 'architecture_repository.dart';
import 'board_store.dart';
import 'board_requests_repository.dart';

typedef ProjectSummary = ({int blocks, int processes, int arrows});

/// The catalog never contains board contents. Each board has its own storage key.
class ProjectsRepository extends ChangeNotifier {
  ProjectsRepository({
    required BoardStore catalog,
    required this.boardStore,
    this.requestsStore,
    required String initialName,
    this.readOnly = false,
  }) : _catalog = CheckedBoardStore(catalog) {
    try {
      final raw = _catalog.read();
      if (raw == null) {
        _projects = [Project(id: Project.defaultId, name: initialName)];
      } else {
        final json = jsonDecode(raw) as Map;
        final ids = <String>{};
        final projects = (json['projects'] as List).map((row) {
          final id = row['id'] as String;
          final name = row['name'] as String;
          if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
              !ids.add(id) ||
              name.trim().isEmpty) {
            throw const FormatException('Invalid project');
          }
          return Project(id: id, name: name);
        }).toList();
        final active = json['activeId'] as String?;
        if (active != null && !ids.contains(active)) {
          throw const FormatException('Unknown active project');
        }
        _projects = projects;
        activeId = active;
      }
    } catch (_) {
      storageError = StorageFailure.read;
      _loadFailed = true;
    }
  }

  final BoardStore _catalog;
  final BoardStore Function(String key) boardStore;
  final BoardStore Function(String key)? requestsStore;
  final bool readOnly;
  final _random = Random.secure();
  List<Project> _projects = [];
  List<Project> get projects => List.unmodifiable(_projects);
  String? activeId;
  StorageFailure? storageError;
  bool _loadFailed = false;
  bool get canEdit =>
      !_loadFailed && !readOnly && storageError != StorageFailure.conflict;

  Project project(String id) => _projects.firstWhere((p) => p.id == id);
  ArchitectureRepository openBoard(String id) => ArchitectureRepository(
    store: boardStore(project(id).boardKey),
    readOnly: readOnly,
  );
  BoardRequestsRepository openRequests(String id) => BoardRequestsRepository(
    store: (requestsStore ?? boardStore)(project(id).requestsKey),
    readOnly: readOnly,
  );

  void _commit(List<Project> projects, String? active) {
    if (_loadFailed) throw StateError('Saved projects could not be read');
    if (readOnly) throw const StorageConflict();
    try {
      _catalog.write(
        jsonEncode({
          'projects': projects.map((p) => p.toJson()).toList(),
          'activeId': active,
        }),
      );
    } on StorageConflict {
      storageError = StorageFailure.conflict;
      notifyListeners();
      rethrow;
    } catch (_) {
      storageError = StorageFailure.write;
      notifyListeners();
      rethrow;
    }
    _projects = projects;
    activeId = active;
    storageError = null;
    notifyListeners();
  }

  String _newId() {
    String id;
    do {
      id =
          'p-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(0x100000000).toRadixString(16)}';
    } while (_projects.any((p) => p.id == id));
    return id;
  }

  String _requireName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Project name is required');
    }
    return trimmed;
  }

  Project create(String name, {String? id}) {
    final resolvedId = id ?? _newId();
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(resolvedId) ||
        _projects.any((project) => project.id == resolvedId)) {
      throw const FormatException('Invalid project id');
    }
    final created = Project(id: resolvedId, name: _requireName(name));
    _commit([..._projects, created], activeId);
    return created;
  }

  /// Add a project with a complete starter board, without replacing an
  /// existing catalog entry or a previously saved board with the same ID.
  Project ensureWithBoard({
    required String id,
    required String name,
    required Map<String, dynamic> document,
  }) {
    for (final existing in _projects) {
      if (existing.id == id) return existing;
    }
    if (_loadFailed) throw StateError('Saved projects could not be read');
    if (readOnly || storageError == StorageFailure.conflict) {
      throw const StorageConflict();
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid project id');
    }

    final created = Project(id: id, name: _requireName(name));
    final target = CheckedBoardStore(boardStore(created.boardKey));
    final saved = target.read();
    final validator = ArchitectureRepository();
    try {
      if (saved == null) {
        validator.replace(document);
        target.write(jsonEncode(validator.snapshot()));
      } else {
        validator.replace(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      }
    } finally {
      validator.dispose();
    }
    _commit([..._projects, created], activeId);
    _summaries.remove(created.id);
    return created;
  }

  /// Copy a board into a new project. Agent requests stay with the source,
  /// the same way an exported diagram leaves them behind.
  Project duplicate(String id, String name) {
    final source = project(id);
    final trimmed = _requireName(name);
    if (_loadFailed) throw StateError('Saved projects could not be read');
    if (readOnly) throw const StorageConflict();
    final raw = CheckedBoardStore(boardStore(source.boardKey)).read();
    final created = Project(id: _newId(), name: trimmed);
    if (raw != null) {
      // Written before the catalog entry: a failed copy leaves no project.
      final target = CheckedBoardStore(boardStore(created.boardKey))..read();
      target.write(raw);
    }
    _commit([..._projects, created], activeId);
    _summaries.remove(created.id);
    return created;
  }

  final Map<String, ProjectSummary?> _summaries = {};

  /// Counts for the projects list. `null` when the board cannot be read;
  /// results are cached until [forgetSummaries].
  ProjectSummary? summary(String id) => _summaries.putIfAbsent(id, () {
    try {
      final raw = boardStore(project(id).boardKey).read();
      if (raw == null) return (blocks: 0, processes: 0, arrows: 0);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      int count(String key) => (json[key] as List?)?.length ?? 0;
      return (
        blocks: count('nodes'),
        processes: count('groups'),
        arrows: count('edges'),
      );
    } catch (_) {
      return null;
    }
  });

  void forgetSummaries() => _summaries.clear();

  void rename(String id, String name) {
    project(id);
    if (name.trim().isEmpty) {
      throw const FormatException('Project name is required');
    }
    _commit([
      for (final p in _projects)
        p.id == id ? Project(id: id, name: name.trim()) : p,
    ], activeId);
  }

  void select(String? id) {
    if (id != null) project(id);
    if (readOnly) {
      activeId = id;
      notifyListeners();
      return;
    }
    _commit(_projects, id);
  }

  /// Hide from the catalog; keep its board bytes for recovery.
  void remove(String id) {
    project(id);
    _commit(
      _projects.where((p) => p.id != id).toList(),
      activeId == id ? null : activeId,
    );
  }

  void restore(Project project) {
    if (_projects.any((p) => p.id == project.id)) return;
    _commit([..._projects, project], activeId);
  }
}
