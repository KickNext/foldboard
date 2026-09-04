import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/architecture_repository.dart';
import '../../../../data/repositories/projects_repository.dart';
import '../../../../domain/models/project.dart';
import '../../../../domain/models/agent_protocol.dart';
import '../../../../domain/examples/example_project.dart';
import '../../../../l10n/l10n.dart';
import '../../../../webmcp/foldboard_webmcp.dart';
import '../../../../data/services/browser_platform.dart';
import '../../planner/view_models/planner_view_model.dart';

class ProjectsViewModel extends ChangeNotifier {
  ProjectsViewModel({required this.repository}) {
    repository.addListener(notifyListeners);
    if (repository.activeId case final String id) {
      _plannerId = id;
      _planner = PlannerViewModel(
        repository: repository.openBoard(id),
        requests: repository.openRequests(id),
        registerBridge: false,
      );
      _planner!.agentCanWrite = () => agentCanWrite();
    }
    webMcp = FoldboardWebMcpCatalog(invoke: invokeTool);
    BrowserPlatform.setFlush(flush);
  }
  final ProjectsRepository repository;
  late final FoldboardWebMcpCatalog webMcp;
  bool Function() agentCanWrite = () => true;
  PlannerViewModel? _planner;
  String? _plannerId;
  final Map<String, BoardHistory> _histories = {};
  PlannerViewModel? get planner => _planner;
  List<Project> get projects => repository.projects;
  ProjectSummary? summary(String id) => repository.summary(id);
  Project? get activeProject => repository.activeId == null
      ? null
      : repository.project(repository.activeId!);
  AppLocalizations strings = lookupAppLocalizations(defaultAppLocale);
  StorageFailure? _operationError;
  String? _actionError;
  int feedbackVersion = 0;
  String? get warning => switch (repository.storageError ?? _operationError) {
    StorageFailure.read => strings.projectsReadFailed,
    StorageFailure.write => strings.projectsWriteFailed,
    StorageFailure.conflict => strings.storageConflict,
    null => _actionError,
  };

  void flush() => _planner?.repository.flush();

  void _flushBeforeLeaving() {
    _checkDraft();
    flush();
    if (_planner?.repository.pendingSave == true) {
      _operationError = StorageFailure.write;
      throw StateError('Save failed; export the current board before leaving');
    }
  }

  void _checkDraft() {
    if (_planner?.hasRequestDraft?.call() == true) {
      throw const AgentException(
        'unsaved-draft',
        'The user has an unsaved request. Ask them to save or discard it before switching projects.',
      );
    }
  }

  bool _run(VoidCallback action) {
    feedbackVersion++;
    repository.forgetSummaries();
    try {
      _operationError = null;
      _actionError = null;
      action();
      notifyListeners();
      return true;
    } catch (_) {
      _actionError = strings.projectsActionFailed;
      notifyListeners();
      return false;
    }
  }

  void _disposePlanner() {
    final old = _planner;
    if (old != null && _plannerId != null) {
      _histories[_plannerId!] = old.repository.saveHistory();
    }
    _planner = null;
    _plannerId = null;
    old?.dispose();
    old?.repository.dispose();
  }

  void _open(String id) {
    if (repository.activeId == id && _planner != null) return;
    _flushBeforeLeaving();
    final board = repository.openBoard(id);
    if (board.storageError == StorageFailure.read) {
      board.dispose();
      _operationError = StorageFailure.read;
      throw StateError('Project board could not be read');
    }
    try {
      repository.select(id);
    } catch (_) {
      board.dispose();
      rethrow;
    }
    _disposePlanner();
    if (_histories[id] case final history?) board.restoreHistory(history);
    _plannerId = id;
    _planner =
        PlannerViewModel(
            repository: board,
            requests: repository.openRequests(id),
            registerBridge: false,
          )
          ..strings = strings
          ..agentCanWrite = (() => agentCanWrite());
  }

  bool open(String id) => _run(() => _open(id));
  bool openExample() => _run(() {
    _flushBeforeLeaving();
    final project = repository.ensureWithBoard(
      id: exampleProjectId,
      name: exampleProjectName,
      document: exampleProjectDocument(),
    );
    _open(project.id);
  });
  bool create(String name, {String? id}) => _run(() {
    _flushBeforeLeaving();
    final project = repository.create(name, id: id);
    _open(project.id);
  });
  bool duplicate(String id, String name) => _run(() {
    _flushBeforeLeaving();
    repository.duplicate(id, name);
  });
  bool rename(String id, String name) =>
      _run(() => repository.rename(id, name));
  bool remove(String id) => _run(() {
    _flushBeforeLeaving();
    repository.remove(id);
    if (_planner != null && repository.activeId == null) _disposePlanner();
  });
  bool restore(Project project) => _run(() => repository.restore(project));
  bool showProjects() => _run(() {
    _flushBeforeLeaving();
    repository.select(null);
    _disposePlanner();
  });

  Map<String, dynamic> handleTool(String tool, Map<String, dynamic> arguments) {
    try {
      final args = Map<String, dynamic>.from(arguments);
      switch (tool) {
        case 'list-projects':
          return {
            'ok': true,
            'projects': projects.map((p) => p.toJson()).toList(),
            'activeProjectId': activeProject?.id,
          };
        case 'create-project':
          if (!agentCanWrite() || !repository.canEdit) {
            throw const AgentException(
              'read-only',
              'Agent editing is disabled.',
            );
          }
          final name = (args['name'] as String).trim();
          if (name.isEmpty) {
            throw const AgentException(
              'invalid-arguments',
              'Project name is required.',
            );
          }
          final rawRequestId = args['clientRequestId'];
          if (rawRequestId != null &&
              (rawRequestId is! String ||
                  rawRequestId.trim().isEmpty ||
                  rawRequestId.length > 128)) {
            throw const AgentException(
              'invalid-arguments',
              'clientRequestId must be a non-empty string up to 128 characters.',
            );
          }
          final requestId = (rawRequestId as String?)?.trim();
          final projectId = requestId == null
              ? null
              : 'agent-${base64Url.encode(utf8.encode(requestId)).replaceAll('=', '')}';
          final existing = projectId == null
              ? null
              : projects
                    .where((project) => project.id == projectId)
                    .firstOrNull;
          if (existing != null) {
            if (existing.name != name) {
              throw const AgentException(
                'idempotency-conflict',
                'clientRequestId was already used with different arguments.',
              );
            }
            if (!open(existing.id)) throw StateError(warning!);
            return {
              'ok': true,
              'project': activeProject!.toJson(),
              'replayed': true,
            };
          }
          _checkDraft();
          if (!create(name, id: projectId)) throw StateError(warning!);
          return {
            'ok': true,
            'project': activeProject!.toJson(),
            'replayed': false,
          };
        case 'open-project':
          if (!projects.any((p) => p.id == args['id'])) {
            throw const AgentException('unknown-id', 'Project not found.');
          }
          if (args['id'] != activeProject?.id) _checkDraft();
          if (!open(args['id'] as String)) throw StateError(warning!);
          return {'ok': true, 'project': activeProject!.toJson()};
        default:
          if (_planner == null) {
            throw const AgentException(
              'no-project',
              'Open a project first using open-project',
            );
          }
          // A caller can pin the project to avoid modifying a different board
          // if a human switches projects between tool calls.
          if (args['projectId'] != null &&
              args['projectId'] != activeProject!.id) {
            throw const AgentException(
              'project-conflict',
              'Active project changed. Read the project again.',
            );
          }
          final result = _planner!.handleTool(tool, args);
          result['project'] = activeProject!.toJson();
          return result;
      }
    } catch (e) {
      return {
        ...agentFailure(e, _planner?.repository.revision),
        'projectId': activeProject?.id,
      };
    }
  }

  Map<String, dynamic> invokeTool(
    String name,
    Map<String, dynamic> arguments,
  ) => handleTool(name, arguments);

  @override
  void dispose() {
    BrowserPlatform.setFlush(null);
    repository.removeListener(notifyListeners);
    _disposePlanner();
    super.dispose();
  }
}
