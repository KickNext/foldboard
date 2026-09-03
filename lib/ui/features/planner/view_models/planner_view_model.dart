import 'dart:convert';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../data/repositories/architecture_repository.dart';
import '../../../../domain/models/architecture_models.dart';
import '../../../../domain/use_cases/auto_layout_architecture.dart';
import '../../../../domain/use_cases/level_layout.dart';
import '../../../../domain/use_cases/agent_queries.dart';
import '../../../../domain/use_cases/export_architecture_markdown.dart';
import '../../../../domain/use_cases/export_architecture_mermaid.dart';
import '../../../../domain/use_cases/trace_path.dart';
import '../../../../domain/models/agent_protocol.dart';
import '../../../../data/repositories/board_store.dart';
import '../../../../data/repositories/board_requests_repository.dart';
import '../../../../domain/models/board_request.dart';
import '../../../../webmcp/webmcp_bridge.dart';

import 'level_graph.dart';
import 'board_search_result.dart';
import 'layout_route_metrics.dart';

enum CanvasTool { select, pan }

/// How much of a trace is on screen at once: the board's own cards in a line,
/// or the whole thread as text with every description in full.
enum TraceDensity { cards, read }

/// One row of a trace as it is shown. Either a step of the thread, or a fold
/// standing for the run of steps folded back into it.
class TraceItem {
  const TraceItem({
    required this.id,
    required this.title,
    required this.description,
    required this.foldPath,
    required this.isCollapsedFold,
    required this.isFold,
    required this.stepIndex,
    required this.stepCount,
    required this.branchTargets,
    required this.isAnchor,
  });

  final String id;
  final String title;
  final String description;
  final List<String> foldPath;

  /// True when this row stands for steps hidden inside it.
  final bool isCollapsedFold;
  final bool isFold;

  /// First step of the thread this row covers, and how many it covers.
  final int stepIndex;
  final int stepCount;
  final List<String> branchTargets;
  final bool isAnchor;

  int get depth => foldPath.length;
  bool covers(int step) => step >= stepIndex && step < stepIndex + stepCount;
}

/// A detached copy of one card. For a process it carries the whole subtree
/// and the arrows that live entirely inside it; arrows crossing the boundary
/// are dropped, because their other end is not part of the copy.
class BoardClipboard {
  const BoardClipboard({
    required this.rootId,
    required this.rootIds,
    required this.title,
    required this.nodes,
    required this.groups,
    required this.edges,
  });
  final String rootId;
  final Set<String> rootIds;
  final String title;
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> edges;
}

class PlannerViewModel extends ChangeNotifier {
  PlannerViewModel({
    required this.repository,
    BoardRequestsRepository? requests,
    this._autoLayout = const AutoLayoutArchitecture(),
    bool registerBridge = true,
  }) : requests = requests ?? BoardRequestsRepository() {
    repository.addListener(_repositoryChanged);
    this.requests.addListener(notifyListeners);
    if (registerBridge) {
      WebMcpBridge.initialize(handleToolCall, repository.flush);
    }
  }
  final ArchitectureRepository repository;
  final BoardRequestsRepository requests;
  bool Function() agentCanWrite = () => true;
  bool Function()? hasRequestDraft;
  Map<String, dynamic> Function()? readViewport;
  Set<String> agentChangedIds = {};
  int agentChangeVersion = 0;
  int? agentChangeRevision;
  int agentChangeCount = 0;
  Timer? _agentHighlightTimer;
  bool get canUndoAgentChange =>
      canEdit &&
      !repository.transactionActive &&
      agentChangeRevision == repository.revision &&
      repository.canUndo;
  void dismissAgentChange() {
    agentChangeRevision = null;
    notifyListeners();
  }

  void undoAgentChange() {
    if (!canUndoAgentChange) return;
    undo();
    agentChangeRevision = null;
    notifyListeners();
  }

  Map<String, dynamic> userContext({bool viewport = false}) => {
    'levelId': currentLevelId,
    'selectedIds': [...selectedCardIds, ?selectedEdgeId],
    'selectionIsReference': selectedIsReference,
    if (selectedEdgeId != null) 'sourceEdgeIds': selectedConnectionIds,
    'mode': connectFrom != null ? 'draw-arrow' : canvasTool.name,
    'agentCanWrite': agentCanWrite() && canEdit,
    'pendingRequests': requests.loadFailed ? null : requests.pendingCount,
    'requestsRevision': requests.revision,
    if (viewport) 'viewport': readViewport?.call(),
  };

  Map<String, dynamic> captureRequestContext() => {
    'levelId': currentLevelId,
    'levelTitle': levelPath.lastOrNull?.title ?? strings.rootLevel,
    'boardRevision': repository.revision,
    'selectionIsReference': selectedIsReference,
    'targets': [
      for (final id in selectedCardIds)
        if (nodes.where((node) => node.id == id).firstOrNull case final node?)
          {'id': node.id, 'title': node.title, 'type': 'node'}
        else if (groups.where((group) => group.id == id).firstOrNull
            case final group?)
          {'id': group.id, 'title': group.title, 'type': 'group'},
      if (selectedEdgeId != null)
        for (final edge in edges.where(
          (e) => selectedConnectionIds.contains(e.id),
        ))
          {'id': edge.id, 'title': '${edge.from} → ${edge.to}', 'type': 'edge'},
    ],
    'viewport': readViewport?.call(),
  };

  /// Card IDs targeted by pending human requests, for on-board markers.
  Set<String> get pendingRequestTargetIds => requests.loadFailed
      ? const {}
      : {
          for (final item in requests.items)
            if (item.status == 'pending')
              for (final target in item.targets) target['id'] as String,
        };

  String? agentRespondedRequestId;
  int agentResponseVersion = 0;
  void dismissAgentResponse() {
    agentRespondedRequestId = null;
    notifyListeners();
  }

  /// Cards anchored by the request draft being written, kept highlighted so
  /// a selection change never silently retargets the visible anchor.
  Set<String> commentDraftTargetIds = const {};
  void setCommentDraftTargets(Iterable<String> ids) {
    final next = ids.toSet();
    if (setEquals(next, commentDraftTargetIds)) return;
    commentDraftTargetIds = next;
    notifyListeners();
  }

  /// Pending requests whose captured targets intersect [ids], newest first.
  List<BoardRequest> pendingRequestsFor(Iterable<String> ids) {
    if (requests.loadFailed) return const [];
    final set = ids.toSet();
    return [
      for (final item in requests.items.reversed)
        if (item.status == 'pending' &&
            item.targets.any((t) => set.contains(t['id'])))
          item,
    ];
  }

  Map<String, dynamic> requestDetails(BoardRequest item) {
    final live = {
      ...nodes.map((n) => n.id),
      ...groups.map((g) => g.id),
      ...edges.map((e) => e.id),
    };
    return {
      ...item.toJson(),
      'missingTargetIds': [
        for (final t in item.targets)
          if (!live.contains(t['id'])) t['id'],
      ],
    };
  }

  AppLocalizations strings = lookupAppLocalizations(defaultAppLocale);
  final AutoLayoutArchitecture _autoLayout;
  final _arrangeViewports = <String?, Size>{};
  String? currentLevelId;
  LevelGraph? _levelGraph;
  LevelGraph get levelGraph => _levelGraph ??= LevelGraph.build(
    levelId: currentLevelId,
    nodes: nodes,
    groups: groups,
    edges: edges,
    referencePositions: repository.referencePositions(currentLevelId),
    connectionFrom: connectFrom,
  );
  List<ArchitectureNode> get canvasNodes => levelGraph.nodes;
  List<ArchitectureEdge> get canvasEdges => levelGraph.edges;
  List<ArchitectureGroup> get levelPath {
    final path = <ArchitectureGroup>[];
    var id = currentLevelId;
    while (id != null) {
      final group = groups.where((g) => g.id == id).firstOrNull;
      if (group == null) break;
      path.insert(0, group);
      id = group.parentId;
    }
    return path;
  }

  List<String> get selectedConnectionIds => selectedEdgeId == null
      ? const []
      : levelGraph.edgeSources[selectedEdgeId] ?? [selectedEdgeId!];

  void openLevel(String? id) {
    if (id == currentLevelId) return;
    if (id != null && !groups.any((g) => g.id == id)) return;
    currentLevelId = id;
    _levelGraph = null;
    cameraTargetId = null;
    referenceTargetId = null;
    cameraRequestVersion++;
    _select();
  }

  void revealObject(String id) {
    final node = nodes.where((n) => n.id == id).firstOrNull;
    final group = groups.where((g) => g.id == id).firstOrNull;
    if (node == null && group == null) return;
    referenceTargetId = null;
    openLevel(node?.parentId ?? group?.parentId);
    node != null ? select(id) : selectGroup(id);
    focusSelection();
  }

  /// Follow a visible boundary reference without treating it as a search zoom.
  void openReference(String id) {
    if (!levelGraph.referenceIds.contains(id)) return;
    final node = nodes.where((n) => n.id == id).firstOrNull;
    final group = groups.where((g) => g.id == id).firstOrNull;
    if (node == null && group == null) return;
    openLevel(node?.parentId ?? group?.parentId);
    referenceTargetId = id;
    node != null ? select(id) : selectGroup(id);
  }

  // --- Trace ---------------------------------------------------------------
  // One straightened thread through the board. A lens over the same document:
  // it reads, it never writes, and it leaves the level underneath untouched so
  // closing it returns to exactly the board that was there.

  Trace? trace;
  TraceDensity traceDensity = TraceDensity.cards;
  final Set<String> _traceCollapsed = {};
  Set<String> get traceCollapsed => Set.unmodifiable(_traceCollapsed);

  /// Index into `trace.steps`, not into the rows on screen: a collapsed fold
  /// hides steps without moving the thread underneath.
  int traceFocus = 0;
  int traceVersion = 0;
  bool get tracing => trace != null;

  String traceFoldTitle(String id) =>
      groups.where((g) => g.id == id).firstOrNull?.title ?? id;

  /// Cards the thread is pinned to. A pinned end stops the thread there
  /// instead of letting it run on to the board's own source or sink; both
  /// pinned trace the segment between them, and the same card at both ends
  /// traces the loop through it.
  String? tracePinnedFrom;
  String? tracePinnedTo;

  /// Opens a thread. See [TracePath] for what the pins mean. Returns false and
  /// leaves any open trace alone when there is nothing to show.
  bool startTrace({
    String? anchorId,
    String? fromId,
    String? toId,
    String? cameFromId,
  }) {
    final next = const TracePath()(
      nodes: nodes,
      groups: groups,
      edges: edges,
      anchorId: anchorId,
      fromId: fromId,
      toId: toId,
      cameFromId: cameFromId,
    );
    if (next == null || next.steps.isEmpty) {
      error = fromId != null && fromId == toId
          ? strings.traceNoLoop
          : fromId != null && toId != null
          ? strings.traceNoConnection
          : strings.traceNothingToFollow;
      notifyListeners();
      return false;
    }
    trace = next;
    tracePinnedFrom = fromId;
    tracePinnedTo = toId;
    traceFocus = next.anchorIndex;
    _traceCollapsed.clear();
    traceVersion++;
    notifyListeners();
    return true;
  }

  /// The entry the board offers for whatever is currently selected: an arrow
  /// is traced through, two cards are traced between, one card is traced from.
  void startTraceFromSelection() {
    final edge = selectedEdge;
    if (edge != null) {
      startTrace(anchorId: edge.to, cameFromId: edge.from);
      return;
    }
    if (hasMultipleSelection) {
      final ids = _selectedCardIds.toList();
      startTrace(fromId: ids.first, toId: ids.last);
      return;
    }
    startTrace(anchorId: selectedId ?? selectedGroupId);
  }

  /// Pins where the thread starts, keeping the end it already had. Selection
  /// only reaches the current level, so these come from a search of the whole
  /// board instead.
  void traceStartAt(String id) =>
      startTrace(fromId: id, toId: tracePinnedTo, anchorId: id);

  /// Pins where the thread ends. Without a pinned start the thread runs back
  /// from here to its own source.
  void traceEndAt(String id) =>
      startTrace(fromId: tracePinnedFrom, toId: id, anchorId: id);

  /// Lets a pinned end go, so the thread runs on to the board's own source or
  /// sink again.
  void unpinTrace({required bool start}) {
    final keep = start ? tracePinnedTo : tracePinnedFrom;
    startTrace(
      fromId: start ? null : keep,
      toId: start ? keep : null,
      anchorId: trace?.anchor?.id ?? keep,
    );
  }

  void exitTrace() {
    if (trace == null) return;
    trace = null;
    tracePinnedFrom = null;
    tracePinnedTo = null;
    _traceCollapsed.clear();
    traceFocus = 0;
    notifyListeners();
  }

  void setTraceDensity(TraceDensity value) {
    if (traceDensity == value) return;
    traceDensity = value;
    notifyListeners();
  }

  void collapseTraceFold(String id) {
    if (!_traceCollapsed.add(id)) return;
    notifyListeners();
  }

  void expandTraceFold(String id) {
    if (!_traceCollapsed.remove(id)) return;
    notifyListeners();
  }

  void expandTraceFolds() {
    if (_traceCollapsed.isEmpty) return;
    _traceCollapsed.clear();
    notifyListeners();
  }

  /// The rows on screen: steps, with every collapsed fold standing for the run
  /// of steps it swallowed.
  List<TraceItem> get traceItems {
    final current = trace;
    if (current == null) return const [];
    final steps = current.steps;
    final owners = [
      for (final step in steps)
        step.foldPath.where(_traceCollapsed.contains).firstOrNull,
    ];
    final items = <TraceItem>[];
    var index = 0;
    while (index < steps.length) {
      final owner = owners[index];
      if (owner == null) {
        final step = steps[index];
        items.add(
          TraceItem(
            id: step.id,
            title: step.title,
            description: step.description,
            foldPath: step.foldPath,
            isCollapsedFold: false,
            isFold: step.isFold,
            stepIndex: index,
            stepCount: 1,
            branchTargets: step.branchTargets,
            isAnchor: index == current.anchorIndex,
          ),
        );
        index++;
        continue;
      }
      var last = index;
      while (last + 1 < steps.length && owners[last + 1] == owner) {
        last++;
      }
      final depth = steps[index].foldPath.indexOf(owner);
      items.add(
        TraceItem(
          id: owner,
          title: traceFoldTitle(owner),
          description:
              groups.where((g) => g.id == owner).firstOrNull?.description ?? '',
          foldPath: steps[index].foldPath.sublist(0, depth < 0 ? 0 : depth),
          isCollapsedFold: true,
          isFold: true,
          stepIndex: index,
          stepCount: last - index + 1,
          branchTargets: const [],
          isAnchor: current.anchorIndex >= index && current.anchorIndex <= last,
        ),
      );
      index = last + 1;
    }
    return List.unmodifiable(items);
  }

  TraceItem? get focusedTraceItem =>
      traceItems.where((item) => item.covers(traceFocus)).firstOrNull;

  void focusTraceStep(int stepIndex) {
    final current = trace;
    if (current == null) return;
    final clamped = stepIndex.clamp(0, current.steps.length - 1);
    if (traceFocus == clamped) return;
    traceFocus = clamped;
    notifyListeners();
  }

  /// Walks the thread one row at a time. A collapsed fold is one row, however
  /// many steps are folded into it.
  void stepTrace(int delta) {
    final items = traceItems;
    if (items.isEmpty) return;
    var index = items.indexWhere((item) => item.covers(traceFocus));
    if (index < 0) index = 0;
    final next = (index + delta).clamp(0, items.length - 1);
    if (items[next].stepIndex == traceFocus) return;
    traceFocus = items[next].stepIndex;
    notifyListeners();
  }

  /// Lays the thread through a continuation this step did not take. A branch
  /// leaves the ends free: the point is to see where the other line goes.
  void traceBranch(String fromId, String targetId) =>
      startTrace(anchorId: targetId, cameFromId: fromId);

  /// Switches to the first branch of the focused step, for the keyboard.
  void traceBranchAtFocus() {
    final item = focusedTraceItem;
    if (item == null || item.branchTargets.isEmpty) return;
    traceBranch(item.id, item.branchTargets.first);
  }

  /// Leaves the trace and opens the step where it actually lives.
  void openTraceStep(String id) {
    exitTrace();
    revealObject(id);
  }

  /// Editing from inside a trace touches a card's own words and nothing else.
  /// The order of the thread is a reading of the arrows, so it cannot be
  /// rewired from here.
  void updateTraceStep(String id, {String? title, String? description}) {
    if (trace == null || !canEdit) return;
    final isFold = groups.any((group) => group.id == id);
    final change = {'id': id, 'title': ?title, 'description': ?description};
    _change({
      if (isFold) 'groups': [change] else 'nodes': [change],
    }, historyKey: '$id:${title != null ? 'title' : 'description'}');
  }

  String traceMarkdown() {
    final current = trace;
    if (current == null) return '';
    return traceToMarkdown(current, traceFoldTitle);
  }

  void selectCard(String id) {
    if (connectFrom != null) {
      completeConnection(id);
    } else if (levelGraph.referenceIds.contains(id)) {
      // Select the visible proxy without navigating to the original's level.
      groups.any((group) => group.id == id)
          ? _select(group: id)
          : _select(node: id);
    } else if (levelGraph.processIds.contains(id)) {
      selectGroup(id);
    } else {
      select(id);
    }
  }

  void focusCard(String id) {
    if (selectedId == id || selectedGroupId == id) return;
    groups.any((g) => g.id == id) ? _select(group: id) : _select(node: id);
  }

  void moveSelectionTo(String? parent) {
    if (parent != null && !canParent(parent)) return;
    final id = selectedId ?? selectedGroupId;
    setParent(parent);
    if (id != null && error == null) revealObject(id);
  }

  CanvasTool canvasTool = CanvasTool.select;
  String? selectedId;
  String? selectedGroupId;
  String? selectedEdgeId;
  final Set<String> _selectedCardIds = {};
  Set<String> get selectedCardIds => Set.unmodifiable(_selectedCardIds);
  bool get hasMultipleSelection => _selectedCardIds.length > 1;
  String? connectFrom;
  String? _error;
  int feedbackVersion = 0;
  String? get error => _error;
  set error(String? value) {
    _error = value;
    // Repeating the same failed action should show feedback again.
    feedbackVersion++;
  }

  int _nextId = 0;
  int cameraRequestVersion = 0;
  int arrangeVersion = 0;
  String? cameraTargetId;
  String? referenceTargetId;
  List<ArchitectureNode> get nodes => repository.nodes;
  bool get canEdit => repository.canEdit;
  List<ArchitectureGroup> get groups => repository.groups;
  List<ArchitectureEdge> get edges => repository.edges;
  ArchitectureNode? get selectedNode =>
      nodes.where((n) => n.id == selectedId).firstOrNull;
  ArchitectureGroup? get selectedGroup =>
      groups.where((g) => g.id == selectedGroupId).firstOrNull;
  ArchitectureEdge? get selectedEdge =>
      edges.where((e) => e.id == selectedEdgeId).firstOrNull;
  bool get hasSelection => _selectedCardIds.isNotEmpty || selectedEdge != null;
  bool get selectedIsReference =>
      levelGraph.referenceIds.contains(selectedId ?? selectedGroupId);
  List<String> get referenceConnectionIds => {
    ...?levelGraph.referenceSources[selectedId ?? selectedGroupId],
    for (final edge in canvasEdges)
      if (edge.from == (selectedId ?? selectedGroupId) ||
          edge.to == (selectedId ?? selectedGroupId))
        ...?levelGraph.edgeSources[edge.id],
  }.toList();
  List<String> referenceConnectionIdsFor(String id) => {
    ...?levelGraph.referenceSources[id],
    for (final edge in canvasEdges)
      if (edge.from == id || edge.to == id) ...?levelGraph.edgeSources[edge.id],
  }.toList();

  void undo() => _history(repository.undo);
  void redo() => _history(repository.redo);
  void _history(VoidCallback action) {
    final id = selectedId ?? selectedGroupId;
    final parent = selectedNode?.parentId ?? selectedGroup?.parentId;
    try {
      action();
      cancelConnection();
      if (id != null &&
          hasSelection &&
          parent != (selectedNode?.parentId ?? selectedGroup?.parentId)) {
        revealObject(id);
      }
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  String get documentTitle =>
      groups.where((g) => g.parentId == null).firstOrNull?.title ?? 'Foldboard';
  String get selectionTitle => hasMultipleSelection
      ? strings.selectedCards(_selectedCardIds.length)
      // An unnamed card keeps the same fallback the canvas prints; a blank
      // selection bar reads as a rendering bug.
      : switch ((selectedNode, selectedGroup)) {
          (final node?, _) =>
            node.title.isEmpty ? strings.newBlock : node.title,
          (_, final group?) =>
            group.title.isEmpty ? strings.newFold : group.title,
          _ =>
            selectedConnectionIds.length > 1
                ? strings.connectionCount(selectedConnectionIds.length)
                : strings.arrow,
        };
  String? get warning => switch (repository.storageError) {
    StorageFailure.read => strings.storageReadFailed,
    StorageFailure.write => strings.storageWriteFailed,
    StorageFailure.conflict => strings.storageConflict,
    null =>
      error == null
          ? null
          : error == 'ancestor-arrow'
          ? strings.ancestorConnection
          : error == 'duplicate-arrow'
          ? strings.connectionExists
          : error == 'import-invalid'
          ? strings.importInvalid
          : error == 'export-image'
          ? strings.exportImageFailed
          : strings.changeFailed,
  };

  void reportExportFailure() {
    error = 'export-image';
    notifyListeners();
  }

  /// Frame the whole level. The canvas honours this on its next build.
  void fitContent() {
    cameraTargetId = null;
    cameraRequestVersion++;
    notifyListeners();
  }

  void reportImportFailure([Object? cause]) {
    error = cause is AncestorConnectionException
        ? 'ancestor-arrow'
        : 'import-invalid';
    notifyListeners();
  }

  void _repositoryChanged() {
    _levelGraph = null;
    if (currentLevelId != null && !groups.any((g) => g.id == currentLevelId)) {
      currentLevelId = null;
      cameraTargetId = null;
      referenceTargetId = null;
      cameraRequestVersion++;
    }
    final liveCards = {...nodes.map((n) => n.id), ...groups.map((g) => g.id)};
    _selectedCardIds.removeWhere((id) => !liveCards.contains(id));
    if (selectedNode == null || !_selectedCardIds.contains(selectedId)) {
      selectedId = null;
    }
    if (selectedGroup == null || !_selectedCardIds.contains(selectedGroupId)) {
      selectedGroupId = null;
    }
    if (_selectedCardIds.isNotEmpty &&
        selectedId == null &&
        selectedGroupId == null) {
      _setPrimary(_selectedCardIds.last);
    }
    if (selectedEdge == null) selectedEdgeId = null;
    if (!nodes.any((n) => n.id == connectFrom) &&
        !groups.any((g) => g.id == connectFrom)) {
      connectFrom = null;
    }
    if (trace != null) _refreshTrace(liveCards);
    notifyListeners();
  }

  /// A trace is a reading of the board, so an edit underneath it re-straightens
  /// the same thread instead of leaving a stale one on screen.
  void _refreshTrace(Set<String> live) {
    final current = trace!;
    final anchor = current.anchor?.id;
    final focused = traceFocus < current.steps.length
        ? current.steps[traceFocus].id
        : null;
    final from = live.contains(tracePinnedFrom) ? tracePinnedFrom : null;
    final to = live.contains(tracePinnedTo) ? tracePinnedTo : null;
    final next = const TracePath()(
      nodes: nodes,
      groups: groups,
      edges: edges,
      anchorId: anchor != null && live.contains(anchor) ? anchor : null,
      fromId: from,
      toId: to,
    );
    if (next == null || next.steps.isEmpty) {
      trace = null;
      tracePinnedFrom = null;
      tracePinnedTo = null;
      _traceCollapsed.clear();
      traceFocus = 0;
      return;
    }
    tracePinnedFrom = from;
    tracePinnedTo = to;
    trace = next;
    final kept = next.steps.indexWhere((step) => step.id == focused);
    traceFocus = kept >= 0 ? kept : next.anchorIndex;
    _traceCollapsed.removeWhere((id) => !live.contains(id));
  }

  void _select({String? node, String? group, String? edge}) {
    selectedId = node;
    selectedGroupId = group;
    selectedEdgeId = edge;
    _selectedCardIds
      ..clear()
      ..addAll([?node, ?group]);
    notifyListeners();
  }

  void _setPrimary(String? id) {
    selectedId = nodes.any((node) => node.id == id) ? id : null;
    selectedGroupId = groups.any((group) => group.id == id) ? id : null;
  }

  bool isCardSelected(String id) => _selectedCardIds.contains(id);

  void toggleCardSelection(String id) {
    if (connectFrom != null) {
      completeConnection(id);
      return;
    }
    if (!canvasNodes.any((node) => node.id == id)) return;
    selectedEdgeId = null;
    if (!_selectedCardIds.remove(id)) {
      _selectedCardIds.add(id);
      _setPrimary(id);
    } else if (_selectedCardIds.isEmpty) {
      _setPrimary(null);
    } else if (selectedId == id || selectedGroupId == id) {
      _setPrimary(_selectedCardIds.last);
    }
    notifyListeners();
  }

  void selectCards(Iterable<String> ids, {bool additive = false}) {
    final visible = canvasNodes.map((node) => node.id).toSet();
    final next = ids.where(visible.contains).toSet();
    if (!additive) _selectedCardIds.clear();
    _selectedCardIds.addAll(next);
    selectedEdgeId = null;
    _setPrimary(_selectedCardIds.lastOrNull);
    notifyListeners();
  }

  void select(String? id) {
    final node = nodes.where((n) => n.id == id).firstOrNull;
    if (node != null && node.parentId != currentLevelId) {
      currentLevelId = node.parentId;
      referenceTargetId = null;
      _levelGraph = null;
      cameraRequestVersion++;
    }
    _select(node: id);
  }

  void selectGroup(String? id) {
    final group = groups.where((g) => g.id == id).firstOrNull;
    if (group != null && group.parentId != currentLevelId) {
      currentLevelId = group.parentId;
      referenceTargetId = null;
      _levelGraph = null;
      cameraRequestVersion++;
    }
    _select(group: id);
  }

  void selectEdge(String? id) => _select(edge: id);
  void setCanvasTool(CanvasTool value) {
    canvasTool = value;
    cancelConnection();
  }

  List<BoardSearchResult> searchBoard(String query) {
    final groupMap = {for (final group in groups) group.id: group};
    String path(String? parent) {
      final names = <String>[];
      while (parent != null) {
        final group = groupMap[parent];
        if (group == null) break;
        names.insert(0, group.title);
        parent = group.parentId;
      }
      return [strings.rootLevel, ...names].join(' / ');
    }

    final candidates = [
      for (final node in nodes)
        BoardSearchResult(
          id: node.id,
          title: node.title,
          kind: BoardSearchKind.block,
          path: path(node.parentId),
          description: node.description,
        ),
      for (final group in groups)
        BoardSearchResult(
          id: group.id,
          title: group.title,
          kind: BoardSearchKind.process,
          path: path(group.parentId),
          description: group.description,
        ),
    ];
    final normalized = query.trim().toLowerCase();
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final results = candidates.where((r) {
      final text = '${r.title} ${r.description} ${r.path}'.toLowerCase();
      return tokens.every(text.contains);
    }).toList();
    final currentPath = path(currentLevelId);
    int rank(BoardSearchResult result) {
      final title = result.title.toLowerCase();
      if (normalized.isEmpty) {
        return result.path == currentPath ? 0 : 1;
      }
      if (title == normalized) return 0;
      if (title.startsWith(normalized)) return 1;
      if (title.contains(normalized)) return 2;
      return 3;
    }

    results.sort((a, b) {
      final order = rank(a).compareTo(rank(b));
      return order != 0
          ? order
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return results;
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  void focusSelection() {
    cameraTargetId = selectedId ?? selectedGroupId;
    cameraRequestVersion++;
    notifyListeners();
  }

  String newId(String prefix) {
    final ids = {
      ...nodes.map((n) => n.id),
      ...groups.map((g) => g.id),
      ...edges.map((e) => e.id),
    };
    String id;
    do {
      id = '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}';
    } while (ids.contains(id));
    return id;
  }

  bool _change(Map<String, dynamic> changes, {String? historyKey}) {
    try {
      error = null;
      repository.applyChanges(changes, historyKey: historyKey);
      return true;
    } catch (e) {
      error = e is AncestorConnectionException
          ? 'ancestor-arrow'
          : e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Where a new card lands without an explicit position: left of the
  /// visible centre, clear of the details panel that opens on the right.
  /// Viewport coordinates only describe the open level; other levels keep
  /// the fallback.
  Offset _spawnPreferred(Offset fallback, {String? parentId}) {
    if ((parentId ?? currentLevelId) != currentLevelId) return fallback;
    final viewport = readViewport?.call();
    final x = (viewport?['x'] as num?)?.toDouble();
    final y = (viewport?['y'] as num?)?.toDouble();
    final width = (viewport?['width'] as num?)?.toDouble();
    final height = (viewport?['height'] as num?)?.toDouble();
    if (x == null || y == null || width == null || height == null) {
      return fallback;
    }
    return Offset(x + width * .38 - 130, y + height * .5 - 59);
  }

  ArchitectureNode addNode({
    String? title,
    Offset? position,
    String? parentId,
  }) {
    final node = ArchitectureNode(
      id: newId('node'),
      title: title ?? strings.newBlock,
      position:
          position ??
          freePosition(
            parentId ?? currentLevelId,
            preferred: _spawnPreferred(
              const Offset(600, 400),
              parentId: parentId,
            ),
          ),
      parentId: parentId ?? currentLevelId,
    );
    if (_change({
      'nodes': [node.toJson()],
    })) {
      select(node.id);
    }
    return node;
  }

  ArchitectureGroup addGroup({String? parentId, String? title}) {
    final group = ArchitectureGroup(
      id: newId('area'),
      title: title ?? strings.newFold,
      position: freePosition(
        parentId ?? currentLevelId,
        preferred: _spawnPreferred(const Offset(400, 260), parentId: parentId),
      ),
      parentId: parentId ?? currentLevelId,
    );
    if (_change({
      'groups': [group.toJson()],
    })) {
      selectGroup(group.id);
    }
    return group;
  }

  BoardClipboard? _clipboard;
  bool get canPaste => _clipboard != null;

  /// The selected roots and their process subtrees. Source ids stay unchanged;
  /// [paste] remaps the complete detached graph in one operation.
  BoardClipboard? _capture(Iterable<String> ids) {
    final roots = ids.toSet();
    if (roots.isEmpty) return null;
    final rootId = roots.last;
    final rootGroup = groups.where((g) => g.id == rootId).firstOrNull;
    final rootNode = nodes.where((n) => n.id == rootId).firstOrNull;
    if (rootGroup == null && rootNode == null) return null;
    final groupIds = <String>{};
    groupIds.addAll(groups.where((g) => roots.contains(g.id)).map((g) => g.id));
    if (groupIds.isNotEmpty) {
      var changed = true;
      while (changed) {
        changed = false;
        for (final g in groups) {
          if (groupIds.contains(g.parentId) && groupIds.add(g.id)) {
            changed = true;
          }
        }
      }
    }
    final nodeIds = <String>{
      ...nodes.where((n) => roots.contains(n.id)).map((n) => n.id),
      for (final n in nodes)
        if (groupIds.contains(n.parentId)) n.id,
    };
    final scope = {...groupIds, ...nodeIds};
    return BoardClipboard(
      rootId: rootId,
      rootIds: roots,
      title: roots.length == 1
          ? rootGroup?.title ?? rootNode!.title
          : '${roots.length} cards',
      groups: [
        for (final g in groups)
          if (groupIds.contains(g.id)) g.toJson(),
      ],
      nodes: [
        for (final n in nodes)
          if (nodeIds.contains(n.id)) n.toJson(),
      ],
      edges: [
        for (final e in edges)
          if (scope.contains(e.from) && scope.contains(e.to)) e.toJson(),
      ],
    );
  }

  /// External cards are projections of an original elsewhere; copying one
  /// would duplicate the projection, not the card the user is looking at.
  bool get canCopySelection =>
      _selectedCardIds.isNotEmpty &&
      !_selectedCardIds.any(levelGraph.referenceIds.contains);

  bool copySelection() {
    if (!canCopySelection) return false;
    final captured = _capture(_selectedCardIds);
    if (captured == null) return false;
    _clipboard = captured;
    showNotice(strings.copiedCard(captured.title));
    return true;
  }

  bool duplicateSelection() {
    if (!canCopySelection || !canEdit) return false;
    final captured = _capture(_selectedCardIds);
    if (captured == null) return false;
    return paste(payload: captured, offsetFromSource: true);
  }

  /// Place a copy on the current level. Everything below the root keeps its
  /// own coordinates: those belong to inner levels, not to this one.
  bool paste({BoardClipboard? payload, bool offsetFromSource = false}) {
    final data = payload ?? _clipboard;
    if (data == null) {
      showNotice(strings.clipboardEmpty);
      return false;
    }
    if (!canEdit) return false;
    final ids = <String, String>{
      for (final g in data.groups) g['id'] as String: newId('area'),
      for (final n in data.nodes) n['id'] as String: newId('node'),
    };
    final rootId = ids[data.rootId];
    if (rootId == null) return false;
    final source = [
      ...data.groups,
      ...data.nodes,
    ].firstWhere((row) => row['id'] == data.rootId);
    final origin = Offset(
      (source['x'] as num?)?.toDouble() ?? 0,
      (source['y'] as num?)?.toDouble() ?? 0,
    );
    final spot = freePosition(
      currentLevelId,
      preferred: offsetFromSource ? origin + const Offset(36, 36) : origin,
    );
    final delta = spot - origin;
    Map<String, dynamic> remap(Map<String, dynamic> row) {
      final isRoot = data.rootIds.contains(row['id']);
      return {
        ...row,
        'id': ids[row['id']],
        'parentId': isRoot ? currentLevelId : ids[row['parentId']],
        if (isRoot) 'x': ((row['x'] as num?)?.toDouble() ?? 0) + delta.dx,
        if (isRoot) 'y': ((row['y'] as num?)?.toDouble() ?? 0) + delta.dy,
      };
    }

    final applied = _change({
      'groups': [for (final g in data.groups) remap(g)],
      'nodes': [for (final n in data.nodes) remap(n)],
      'edges': [
        for (final e in data.edges)
          {
            ...e,
            'id': newId('edge'),
            'from': ids[e['from']],
            'to': ids[e['to']],
          },
      ],
    });
    if (!applied) return false;
    selectCards(data.rootIds.map((id) => ids[id]!).whereType<String>());
    return true;
  }

  String? notice;
  int noticeVersion = 0;
  void showNotice(String message) {
    notice = message;
    noticeVersion++;
    notifyListeners();
  }

  void dismissNotice() {
    if (notice == null) return;
    notice = null;
    notifyListeners();
  }

  Offset freePosition(
    String? parent, {
    required Offset preferred,
    String? excluding,
  }) {
    final occupied = [
      for (final n in nodes)
        if (n.parentId == parent && n.id != excluding)
          (n.position & const Size(260, 118)).inflate(20),
      for (final g in groups)
        if (g.parentId == parent && g.id != excluding)
          (g.position & const Size(260, 118)).inflate(20),
    ];
    bool free(Offset p) =>
        !occupied.any((rect) => rect.overlaps(p & const Size(260, 118)));
    if (free(preferred)) return preferred;
    for (var ring = 1; ; ring++) {
      for (var y = -ring; y <= ring; y++) {
        for (var x = -ring; x <= ring; x++) {
          if (x.abs() != ring && y.abs() != ring) continue;
          final p = preferred + Offset(x * 300, y * 158);
          if (free(p)) return p;
        }
      }
    }
  }

  Map<String, dynamic> readImport(String raw) {
    if (raw.length > 10 * 1024 * 1024) {
      throw const FormatException('File too large');
    }
    final document = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (!document.containsKey('nodes') && !document.containsKey('groups')) {
      throw const FormatException('Not a Foldboard document');
    }
    final check = ArchitectureRepository();
    try {
      check.replace(document);
      return check.snapshot();
    } finally {
      check.dispose();
    }
  }

  void importDocument(Map<String, dynamic> document) {
    repository.replace(document);
    openLevel(null);
    select(null);
    cameraTargetId = null;
    cameraRequestVersion++;
    notifyListeners();
  }

  void updateSelected({String? title, String? description}) {
    if (selectedNode != null) {
      _change({
        'nodes': [
          {'id': selectedId, 'title': ?title, 'description': ?description},
        ],
      }, historyKey: '$selectedId:${title != null ? 'title' : 'description'}');
    }
    if (selectedGroup != null) {
      _change(
        {
          'groups': [
            {
              'id': selectedGroupId,
              'title': ?title,
              'description': ?description,
            },
          ],
        },
        historyKey:
            '$selectedGroupId:${title != null ? 'title' : 'description'}',
      );
    }
  }

  void setParent(String? parentId) {
    final key = selectedNode != null ? 'nodes' : 'groups';
    final id = selectedId ?? selectedGroupId;
    if (id != null) {
      final object = selectedNode;
      final group = selectedGroup;
      final oldParent = object?.parentId ?? group?.parentId;
      if (oldParent == parentId) return;
      final position = freePosition(
        parentId,
        preferred: object?.position ?? group!.position,
        excluding: id,
      );
      _change({
        key: [
          {'id': id, 'parentId': parentId, 'x': position.dx, 'y': position.dy},
        ],
      });
    }
  }

  bool canParent(String groupId) {
    var id = groupId;
    while (true) {
      if (id == selectedGroupId) return false;
      final parent = groups.where((g) => g.id == id).firstOrNull?.parentId;
      if (parent == null) return true;
      id = parent;
    }
  }

  void setNodePosition(String id, Offset position) {
    try {
      if (levelGraph.referenceIds.contains(id)) {
        if (repository.referencePositions(currentLevelId)[id] == position) {
          return;
        }
        final references = Map<String, dynamic>.from(
          repository.snapshot()['referencePositions'] as Map? ?? const {},
        );
        final levelKey = currentLevelId ?? '';
        final level = Map<String, dynamic>.from(
          references[levelKey] as Map? ?? const {},
        );
        level[id] = {'x': position.dx, 'y': position.dy};
        references[levelKey] = level;
        repository.applyChanges({'referencePositions': references});
        return;
      }
      if (levelGraph.processIds.contains(id)) {
        repository.applyChanges({
          'groups': [
            {'id': id, 'x': position.dx, 'y': position.dy},
          ],
        });
      } else {
        repository.setNodePosition(id, position);
      }
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void setCardPositions(Map<String, Offset> positions) {
    if (positions.isEmpty) return;
    try {
      final references = Map<String, dynamic>.from(
        repository.snapshot()['referencePositions'] as Map? ?? const {},
      );
      final levelKey = currentLevelId ?? '';
      final levelReferences = Map<String, dynamic>.from(
        references[levelKey] as Map? ?? const {},
      );
      final nodeChanges = <Map<String, dynamic>>[];
      final groupChanges = <Map<String, dynamic>>[];
      var referencesChanged = false;
      for (final entry in positions.entries) {
        final position = entry.value;
        if (levelGraph.referenceIds.contains(entry.key)) {
          levelReferences[entry.key] = {'x': position.dx, 'y': position.dy};
          referencesChanged = true;
        } else if (levelGraph.processIds.contains(entry.key)) {
          groupChanges.add({
            'id': entry.key,
            'x': position.dx,
            'y': position.dy,
          });
        } else {
          nodeChanges.add({
            'id': entry.key,
            'x': position.dx,
            'y': position.dy,
          });
        }
      }
      if (referencesChanged) references[levelKey] = levelReferences;
      repository.applyChanges({
        if (nodeChanges.isNotEmpty) 'nodes': nodeChanges,
        if (groupChanges.isNotEmpty) 'groups': groupChanges,
        if (referencesChanged) 'referencePositions': references,
      });
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void nudgeSelection(Offset delta) {
    final visible = {for (final node in canvasNodes) node.id: node};
    setCardPositions({
      for (final id in _selectedCardIds)
        if (visible[id] case final node?) id: node.position + delta,
    });
  }

  void deleteSelected() {
    final id = selectedId ?? selectedGroupId ?? selectedEdgeId;
    final targets = _selectedCardIds.isNotEmpty
        ? {
            for (final cardId in _selectedCardIds)
              if (levelGraph.referenceIds.contains(cardId))
                ...referenceConnectionIdsFor(cardId)
              else
                cardId,
          }.toList()
        : selectedEdgeId != null
        ? selectedConnectionIds
        : const <String>[];
    if (id != null && targets.isNotEmpty && _change({'deleteIds': targets})) {
      select(null);
    }
  }

  void startConnection(String id) {
    if (!canEdit) return;
    connectFrom = id;
    _levelGraph = null;
    notifyListeners();
  }

  void cancelConnection() {
    connectFrom = null;
    if (error == 'duplicate-arrow' || error == 'ancestor-arrow') error = null;
    _levelGraph = null;
    notifyListeners();
  }

  bool canConnectTo(String id) {
    final from = connectFrom;
    return canEdit &&
        from != null &&
        from != id &&
        !repository.connectsAncestor(from, id) &&
        !edges.any((edge) => edge.from == from && edge.to == id);
  }

  void completeConnection(String id, {bool cancelOnError = false}) {
    final from = connectFrom;
    if (from != null && repository.connectsAncestor(from, id)) {
      error = 'ancestor-arrow';
      if (cancelOnError) {
        connectFrom = null;
        _levelGraph = null;
      }
      notifyListeners();
      return;
    }
    if (from != null &&
        edges.any((edge) => edge.from == from && edge.to == id)) {
      error = 'duplicate-arrow';
      if (cancelOnError) {
        connectFrom = null;
        _levelGraph = null;
      }
      notifyListeners();
      return;
    }
    error = null;
    connectFrom = null;
    _levelGraph = null;
    if (from != null && from != id) {
      _change({
        'edges': [
          ArchitectureEdge(id: newId('edge'), from: from, to: id).toJson(),
        ],
      });
    }
    notifyListeners();
  }

  void arrangeCurrent({bool rebuild = false}) {
    try {
      autoArrange(rebuild: rebuild);
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  void autoArrange({
    String? levelId,
    bool useCurrentLevel = true,
    bool rebuild = false,
  }) {
    final scope = useCurrentLevel ? currentLevelId : levelId;
    if (scope != null && !groups.any((g) => g.id == scope)) {
      throw const FormatException('Process not found');
    }
    final graph = scope == currentLevelId
        ? levelGraph
        : LevelGraph.build(
            levelId: scope,
            nodes: nodes,
            groups: groups,
            edges: edges,
            referencePositions: repository.referencePositions(scope),
          );
    if (graph.nodes.isEmpty) return;
    // A reference that feeds this level is an input, even when the process
    // sends something back to it. Keep that feedback out of ranking only;
    // the document and the rendered graph retain every arrow.
    final inputs = {
      for (final edge in graph.edges)
        if (graph.referenceIds.contains(edge.from) &&
            !graph.referenceIds.contains(edge.to))
          edge.from,
    };
    final viewport = readViewport?.call();
    final zoom = (viewport?['zoom'] as num?)?.toDouble() ?? 1;
    // Freeze the layout preference for this level during a session. Resizing
    // the chat or panning must not flip a previously arranged graph.
    final available = _arrangeViewports.putIfAbsent(
      scope,
      () => scope == currentLevelId && viewport != null
          ? Size(
              (viewport['width'] as num).toDouble() * zoom,
              (viewport['height'] as num).toDouble() * zoom,
            )
          : const Size(1280, 800),
    );
    final positions = LevelLayout(ranker: _autoLayout)(
      nodes: graph.nodes.map((n) => n.copyWith(clearParent: true)).toList(),
      edges: graph.edges,
      rankingEdges: graph.edges.where((e) => !inputs.contains(e.to)).toList(),
      viewport: available,
      anchorId: scope == currentLevelId
          ? (selectedId ?? selectedGroupId)
          : null,
      measureRoutes: measureLayoutRoutes,
      mode: rebuild ? LevelLayoutMode.rebuild : LevelLayoutMode.tidy,
    );
    // Reference positions are view-only. Invalidate that view even when no
    // document card moves, and avoid creating a revision for an identical layout.
    _levelGraph = null;
    final changes = {
      'nodes': [
        for (final n in nodes)
          if (n.parentId == scope &&
              positions.containsKey(n.id) &&
              n.position != positions[n.id])
            {'id': n.id, 'x': positions[n.id]!.dx, 'y': positions[n.id]!.dy},
      ],
      'groups': [
        for (final g in groups)
          if (g.parentId == scope &&
              positions.containsKey(g.id) &&
              g.position != positions[g.id])
            {'id': g.id, 'x': positions[g.id]!.dx, 'y': positions[g.id]!.dy},
      ],
    };
    final references = {
      ...?repository.snapshot()['referencePositions'] as Map<String, dynamic>?,
      if (graph.referenceIds.isNotEmpty)
        scope ?? '': {
          for (final id in graph.referenceIds)
            id: {'x': positions[id]!.dx, 'y': positions[id]!.dy},
        },
    };
    final changed =
        changes.values.any((items) => items.isNotEmpty) ||
        jsonEncode(references) !=
            jsonEncode(repository.snapshot()['referencePositions'] ?? {});
    if (!changed) return;
    repository.applyChanges({
      ...changes,
      if (references.isNotEmpty) 'referencePositions': references,
    });
    if (scope == currentLevelId) {
      arrangeVersion++;
    }
    notifyListeners();
  }

  Map<String, dynamic> snapshot() => repository.snapshot();
  Map<String, dynamic> levelSnapshot(String? id) {
    if (id != null && !groups.any((g) => g.id == id)) {
      throw const FormatException('Process not found');
    }
    final graph = LevelGraph.build(
      levelId: id,
      nodes: nodes,
      groups: groups,
      edges: edges,
    );
    return {
      'levelId': id,
      'cards': [
        for (final n in graph.nodes)
          {
            'id': n.id,
            'kind': graph.referenceIds.contains(n.id)
                ? 'reference'
                : graph.processIds.contains(n.id)
                ? 'process'
                : 'block',
            'title': n.title,
          },
      ],
      'connections': [
        for (final e in graph.edges)
          {...e.toJson(), 'sourceEdgeIds': graph.edgeSources[e.id]},
      ],
    };
  }

  String get prettyJson =>
      const JsonEncoder.withIndent('  ').convert(snapshot());
  void exportJson() => WebMcpBridge.download('foldboard.json', prettyJson);

  String markdown({
    String? title,
    Map<String, dynamic>? document,
    bool includeIds = false,
  }) {
    final source = document ?? snapshot();
    return const ExportArchitectureMarkdown()(
      title: title ?? documentTitle,
      revision: source['revision'] as int? ?? repository.revision,
      nodes: [
        for (final item in source['nodes'] as List? ?? const [])
          ArchitectureNode.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      groups: [
        for (final item in source['groups'] as List? ?? const [])
          ArchitectureGroup.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      edges: [
        for (final item in source['edges'] as List? ?? const [])
          ArchitectureEdge.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      includeIds: includeIds,
    );
  }

  void exportMarkdown({String? title}) => WebMcpBridge.download(
    'foldboard.md',
    markdown(title: title),
    type: 'text/markdown',
  );

  String mermaid({String? title, Map<String, dynamic>? document}) {
    final source = document ?? snapshot();
    return const ExportArchitectureMermaid()(
      title: title ?? documentTitle,
      revision: source['revision'] as int? ?? repository.revision,
      nodes: [
        for (final item in source['nodes'] as List? ?? const [])
          ArchitectureNode.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      groups: [
        for (final item in source['groups'] as List? ?? const [])
          ArchitectureGroup.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
      edges: [
        for (final item in source['edges'] as List? ?? const [])
          ArchitectureEdge.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  void exportMermaid({String? title}) => WebMcpBridge.download(
    'foldboard.mmd',
    mermaid(title: title),
    type: 'text/vnd.mermaid',
  );

  Map<String, dynamic> area(String id) {
    final groupIds = <String>{};
    final nodeIds = <String>{};
    if (groups.any((g) => g.id == id)) {
      groupIds.add(id);
      var changed = true;
      while (changed) {
        changed = false;
        for (final g in groups) {
          if (groupIds.contains(g.parentId) && groupIds.add(g.id)) {
            changed = true;
          }
        }
      }
      nodeIds.addAll(
        nodes.where((n) => groupIds.contains(n.parentId)).map((n) => n.id),
      );
    } else if (nodes.any((n) => n.id == id)) {
      nodeIds.add(id);
    } else {
      throw const FormatException('Area not found');
    }
    final scope = {...nodeIds, ...groupIds};
    for (final e in edges) {
      if (scope.contains(e.from)) {
        if (groups.any((g) => g.id == e.to)) {
          groupIds.add(e.to);
        } else {
          nodeIds.add(e.to);
        }
      }
      if (scope.contains(e.to)) {
        if (groups.any((g) => g.id == e.from)) {
          groupIds.add(e.from);
        } else {
          nodeIds.add(e.from);
        }
      }
    }
    for (final n in nodes.where((n) => nodeIds.contains(n.id))) {
      if (n.parentId != null) groupIds.add(n.parentId!);
    }
    for (final initial in groupIds.toList()) {
      var parent = groups.firstWhere((g) => g.id == initial).parentId;
      while (parent != null) {
        groupIds.add(parent);
        parent = groups.firstWhere((g) => g.id == parent).parentId;
      }
    }
    return {
      'revision': repository.revision,
      'nodes': nodes
          .where((n) => nodeIds.contains(n.id))
          .map((n) => n.toJson())
          .toList(),
      'groups': groups
          .where((g) => groupIds.contains(g.id))
          .map((g) => g.toJson())
          .toList(),
      'edges': edges
          .where(
            (e) =>
                (nodeIds.contains(e.from) || groupIds.contains(e.from)) &&
                (nodeIds.contains(e.to) || groupIds.contains(e.to)),
          )
          .map((e) => e.toJson())
          .toList(),
    };
  }

  String handleToolCall(String raw) {
    try {
      final request = jsonDecode(raw) as Map<String, dynamic>;
      final args = Map<String, dynamic>.from(request['args'] as Map? ?? {});
      final tool = request['tool'];
      final result = <String, dynamic>{'ok': true};
      if (args.containsKey('validate') && args['validate'] is! bool) {
        throw const AgentException(
          'invalid-arguments',
          'validate must be a boolean.',
        );
      }
      final dryRun = tool == 'apply-changes' && args['validate'] == true;
      final mutates =
          (tool == 'apply-changes' && !dryRun) || tool == 'auto-arrange';
      if (tool == 'resolve-request' &&
          (!agentCanWrite() || !canEdit || !requests.canEdit)) {
        throw const AgentException(
          'read-only',
          'Agent request updates are disabled.',
        );
      }
      if (mutates && (!agentCanWrite() || !canEdit)) {
        throw const AgentException(
          'read-only',
          'Agent editing is disabled. Reading and export remain available.',
        );
      }
      if (mutates && repository.transactionActive) {
        throw const AgentException(
          'user-busy',
          'The user is dragging cards. Retry when the gesture ends.',
        );
      }
      if (args['return'] != null &&
          !['summary', 'full'].contains(args['return'])) {
        throw const AgentException(
          'invalid-arguments',
          'return must be summary or full.',
        );
      }
      if (tool == 'auto-arrange' &&
          args['mode'] != null &&
          !['tidy', 'rebuild'].contains(args['mode'])) {
        throw const AgentException(
          'invalid-arguments',
          'mode must be tidy or rebuild.',
        );
      }
      if (args['expectedRevision'] != null &&
          args['expectedRevision'] != repository.revision) {
        throw const AgentException(
          'revision-conflict',
          'Read the latest changes before retrying.',
        );
      }
      final before = mutates ? snapshot() : null;
      final beforeRevision = repository.revision;
      int limit(String key, int fallback, int max) {
        final n = args[key] ?? fallback;
        if (n is! int || n < (key == 'limit' ? 1 : 0) || n > max) {
          throw AgentException('invalid-arguments', '$key is out of range.');
        }
        return n;
      }

      bool flag(String key) {
        final value = args[key] ?? false;
        if (value is! bool) {
          throw AgentException('invalid-arguments', '$key must be a boolean.');
        }
        return value;
      }

      switch (tool) {
        case 'list-requests':
          if (requests.loadFailed) {
            throw const AgentException(
              'storage-error',
              'Saved requests could not be loaded.',
            );
          }
          final status = args['status'] ?? 'pending';
          if (!['pending', 'handled', 'all'].contains(status)) {
            throw const AgentException(
              'invalid-arguments',
              'Unknown request status.',
            );
          }
          final items = requests.items
              .where((e) => status == 'all' || e.status == status)
              .toList();
          final offset = limit('offset', 0, 10000000),
              count = limit('limit', 20, 100);
          result.addAll({
            'requestsRevision': requests.revision,
            'total': items.length,
            'requests': [
              for (final item in items.skip(offset).take(count))
                {
                  'id': item.id,
                  'text': item.text.length > 240
                      ? '${item.text.substring(0, 240)}…'
                      : item.text,
                  'textTruncated': item.text.length > 240,
                  'status': item.status,
                  'version': item.version,
                  'targets': item.targets,
                  'levelId': item.context['levelId'],
                  'boardRevision': item.context['boardRevision'],
                },
            ],
            'nextOffset': offset + count < items.length ? offset + count : null,
          });
        case 'get-request':
          if (requests.loadFailed) {
            throw const AgentException(
              'storage-error',
              'Saved requests could not be loaded.',
            );
          }
          result['request'] = requestDetails(
            requests.get(args['id'] as String),
          );
        case 'resolve-request':
          final item = requests.resolve(
            args['id'] as String,
            expectedVersion: args['expectedVersion'] as int,
            response: args['response'] as String?,
          );
          agentRespondedRequestId = item.id;
          agentResponseVersion++;
          result.addAll({
            'requestId': item.id,
            'status': item.status,
            'version': item.version,
            'requestsRevision': requests.revision,
          });
        case 'get-outline':
          result.addAll(
            AgentQueries(
              nodes,
              groups,
              edges,
            ).outline(maxDepth: limit('maxDepth', 8, 128)),
          );
        case 'get-changes':
          if (args['mode'] != null &&
              !['compact', 'events'].contains(args['mode'])) {
            throw const AgentException(
              'invalid-arguments',
              'Unknown changes mode.',
            );
          }
          result.addAll(
            repository.changesSince(
              args['sinceRevision'] as int,
              history: args['historyId'] as String?,
              events: args['mode'] == 'events',
            ),
          );
        case 'get-user-context':
          result['context'] = userContext(viewport: true);
        case 'reveal-card':
          final id = args['id'] as String;
          if (!nodes.any((n) => n.id == id) && !groups.any((g) => g.id == id)) {
            throw const AgentException('unknown-id', 'Card not found.');
          }
          revealObject(id);
          result['revealedId'] = id;
        case 'validate-architecture':
          final issues = AgentQueries(
            nodes,
            groups,
            edges,
          ).validate(maxDepth: limit('maxDepth', 8, 128));
          final offset = limit('offset', 0, 10000000),
              count = limit('limit', 100, 500);
          result.addAll({
            'total': issues.length,
            'issues': issues.skip(offset).take(count).toList(),
            'nextOffset': offset + count < issues.length
                ? offset + count
                : null,
          });
        case 'get-architecture':
          result['architecture'] = snapshot();
          result['view'] = levelSnapshot(currentLevelId);
        case 'search-architecture':
          result.addAll(
            AgentQueries(nodes, groups, edges).search(
              args['query'] as String,
              offset: limit('offset', 0, 10000000),
              limit: limit('limit', 20, 100),
            ),
          );
        case 'get-area':
          final id = args['id'] as String?;
          if (id != null &&
              !nodes.any((n) => n.id == id) &&
              !groups.any((g) => g.id == id)) {
            throw const AgentException('unknown-id', 'Card not found.');
          }
          final includeView = flag('includeView');
          final coordinates = flag('includeCoordinates');
          if (args['return'] == 'full') {
            result['area'] = id == null ? snapshot() : area(id);
          } else {
            final count = limit('limit', 20, 100);
            final edgeCount = limit('edgeLimit', 20, 100);
            if (edgeCount == 0) {
              throw const AgentException(
                'invalid-arguments',
                'edgeLimit must be positive.',
              );
            }
            result.addAll(
              AgentQueries(nodes, groups, edges).readArea(
                id: id,
                maxDepth: limit('maxDepth', 1, 8),
                offset: limit('offset', 0, 10000000),
                limit: count,
                edgeOffset: limit('edgeOffset', 0, 10000000),
                edgeLimit: edgeCount,
                descriptionLimit: limit('descriptionLimit', 500, 10000),
                coordinates: coordinates,
              ),
            );
          }
          if (includeView) {
            result['view'] = levelSnapshot(
              groups.any((g) => g.id == id)
                  ? id
                  : nodes.where((n) => n.id == id).firstOrNull?.parentId,
            );
          }
        case 'apply-changes':
          final changes = Map<String, dynamic>.from(args['changes'] as Map);
          final expected = args['expectedRevision'] as int?;
          if (dryRun) {
            final before = snapshot();
            final preview = repository.previewChanges(
              changes,
              expectedRevision: expected,
              replace: args['replace'] == true,
            );
            final patch = documentDiff(before, preview);
            result.addAll({
              'validated': true,
              'changed': false,
              'wouldChange': patch.isNotEmpty,
              'affectedIds': affectedIds(patch, before: before),
              'summary': changeCounts(before, preview, patch),
            });
            if (args['return'] == 'full') result['architecture'] = preview;
          } else if (args['replace'] == true) {
            repository.replace(changes, expectedRevision: expected);
          } else {
            repository.applyChanges(changes, expectedRevision: expected);
          }
        case 'auto-arrange':
          final id = args['id'] as String?;
          if (id != null && !groups.any((g) => g.id == id)) {
            throw const AgentException('unknown-id', 'Process not found.');
          }
          autoArrange(
            levelId: id,
            useCurrentLevel: args['scope'] == 'current-level',
            rebuild: args['mode'] == 'rebuild',
          );
        case 'export-architecture':
          final format = args['format'] as String? ?? 'json';
          if (!['json', 'markdown'].contains(format)) {
            throw const AgentException(
              'invalid-arguments',
              'Export format must be json or markdown.',
            );
          }
          if (args['includeIds'] != null && args['includeIds'] is! bool) {
            throw const AgentException(
              'invalid-arguments',
              'includeIds must be a boolean.',
            );
          }
          final exportId = args['id'] as String?;
          if (exportId != null &&
              !nodes.any((n) => n.id == exportId) &&
              !groups.any((g) => g.id == exportId)) {
            throw const AgentException('unknown-id', 'Card not found.');
          }
          final document = args['id'] == null
              ? snapshot()
              : area(args['id'] as String);
          if (format == 'markdown') {
            final markdownContent = markdown(
              title: exportId == null
                  ? documentTitle
                  : nodes
                            .where((node) => node.id == exportId)
                            .firstOrNull
                            ?.title ??
                        groups
                            .where((group) => group.id == exportId)
                            .firstOrNull
                            ?.title ??
                        documentTitle,
              document: document,
              includeIds: args['includeIds'] == true,
            );
            result.addAll({
              'format': 'markdown',
              'filename': 'foldboard.md',
              'content': markdownContent,
              'markdown': markdownContent,
            });
          } else {
            final jsonContent = const JsonEncoder.withIndent('  ')
                .convert(document);
            result.addAll({
              'format': 'json',
              'filename': 'foldboard.json',
              'content': jsonContent,
              'json': jsonContent,
            });
          }
        default:
          throw FormatException('Unknown tool: $tool');
      }
      if (mutates) {
        final patch = documentDiff(before!, snapshot());
        final ids = affectedIds(patch, before: before);
        result.addAll({
          'affectedIds': ids,
          'changed': repository.revision != beforeRevision,
        });
        if (args['return'] == 'full') result['architecture'] = snapshot();
        if (repository.revision != beforeRevision && ids.isNotEmpty) {
          agentChangedIds = {
            ...ids,
            for (final e in [
              ...(before['edges'] as List),
              ...snapshot()['edges'] as List,
            ])
              if (ids.contains(e['id'])) ...[
                e['from'] as String,
                e['to'] as String,
              ],
          };
          agentChangeCount = ids.length;
          agentChangeRevision = repository.revision;
          agentChangeVersion++;
          _agentHighlightTimer?.cancel();
          _agentHighlightTimer = Timer(const Duration(seconds: 2), () {
            agentChangedIds = {};
            notifyListeners();
          });
          notifyListeners();
        }
      }
      result['revision'] = repository.revision;
      result['historyId'] = repository.historyId;
      result.putIfAbsent('context', () => userContext());
      return jsonEncode(result);
    } catch (e) {
      return jsonEncode({
        ...agentFailure(
          e is AncestorConnectionException
              ? AgentException('ancestor-arrow', e.message)
              : e is StorageConflict
              ? const AgentException(
                  'storage-conflict',
                  'Another session changed the saved board.',
                )
              : e,
          repository.revision,
        ),
        if (e is AgentException && e.code == 'request-conflict')
          'requestsRevision': requests.revision,
      });
    }
  }

  @override
  void dispose() {
    requests.removeListener(notifyListeners);
    requests.dispose();
    _agentHighlightTimer?.cancel();
    repository.removeListener(_repositoryChanged);
    repository.flush();
    super.dispose();
  }
}
