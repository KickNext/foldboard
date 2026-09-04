import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../../data/services/browser_platform.dart';

import '../../../core/app_theme.dart';
import '../../../core/board_snapshot.dart';
import '../../../core/shortcuts_dialog.dart';
import '../../../core/write_access_scope.dart';
import '../view_models/planner_view_model.dart';
import '../view_models/board_search_result.dart';
import 'widgets/architecture_canvas.dart';
import 'widgets/board_search_dialog.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/floating_inspector.dart';
import 'widgets/board_feedback.dart';
import 'widgets/empty_board_card.dart';
import 'widgets/agent_requests_panel.dart';
import 'widgets/overview_overlay.dart';
import 'widgets/trace_overlay.dart';
import '../../settings/views/settings_page.dart';
import '../../settings/view_models/settings_view_model.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({
    super.key,
    required this.viewModel,
    this.projectTitle,
    this.onProjects,
    this.externalWarning,
    this.externalTicket,
    this.pickJson = BrowserPlatform.pickJson,
  });
  final PlannerViewModel viewModel;
  final String? projectTitle;
  final VoidCallback? onProjects;
  final String? externalWarning;
  final Object? externalTicket;
  final Future<String?> Function() pickJson;
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

/// One export format: its name, its consequence, one tap.
class _ExportFormatTile extends StatelessWidget {
  const _ExportFormatTile({
    super.key,
    required this.value,
    required this.title,
    required this.hint,
  });
  final String value;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      onTap: () => Navigator.pop(context, value),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: BorderSide(color: context.colors.line),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      title: Text(title),
      subtitle: Text(hint),
      trailing: Icon(
        Icons.arrow_forward,
        size: 16,
        color: context.colors.muted,
      ),
    ),
  );
}

class _PlannerPageState extends State<PlannerPage> {
  final _boardFocus = FocusNode(debugLabel: 'Board keyboard');
  final _requestsButtonFocus = FocusNode(debugLabel: 'Agent requests');
  bool _searchOpen = false;
  bool _shortcutsOpen = false;
  bool _deleteDialogOpen = false;
  bool _detailsOpen = false;
  String? _lastLevel;
  bool _importOpen = false;
  bool _leaving = false;
  bool _exportOpen = false;
  final _captureKey = GlobalKey(debugLabel: 'Board capture');
  final _requestsKey = GlobalKey<AgentRequestsPanelState>();
  bool _requestsOpen = false;
  bool _overviewOpen = false;
  bool _wasTracing = false;
  Map<String, dynamic>? _requestsCompose;

  Future<void> _openOverview() async {
    if (_overviewOpen) return;
    if (_requestsOpen &&
        await _requestsKey.currentState?.requestClose(returnFocus: false) !=
            true) {
      return;
    }
    final vm = widget.viewModel;
    if (vm.tracing) vm.exitTrace();
    vm.cancelConnection();
    vm.select(null);
    if (!mounted) return;
    setState(() {
      _overviewOpen = true;
      _detailsOpen = false;
      _requestsOpen = false;
    });
  }

  void _closeOverview() {
    if (!_overviewOpen) return;
    setState(() => _overviewOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _boardFocus.requestFocus();
    });
  }

  void _openOverviewLevel(String? id) {
    widget.viewModel.openLevel(id);
    _closeOverview();
  }

  Future<void> _openDetails() async {
    if (_requestsOpen &&
        await _requestsKey.currentState?.requestClose(returnFocus: false) !=
            true) {
      return;
    }
    if (mounted) setState(() => _detailsOpen = true);
  }

  Future<void> _leaveProject() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final panel = _requestsKey.currentState;
      if (panel != null && !await panel.prepareToLeave()) return;
      if (mounted) widget.onProjects?.call();
    } finally {
      _leaving = false;
    }
  }

  Future<void> _openExport() async {
    if (_exportOpen) return;
    _exportOpen = true;
    try {
      // A choice of formats reads as a list, not as dialog actions: each
      // format carries its own consequence, and the row of buttons used to
      // wrap badly on narrow screens.
      final format = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.exportProject),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ExportFormatTile(
                  key: const Key('confirm-export-diagram'),
                  value: 'json',
                  title: context.l10n.exportJsonFormat,
                  hint: context.l10n.exportJsonHint,
                ),
                _ExportFormatTile(
                  key: const Key('export-markdown'),
                  value: 'markdown',
                  title: context.l10n.exportMarkdown,
                  hint: context.l10n.exportMarkdownHint,
                ),
                _ExportFormatTile(
                  key: const Key('export-mermaid'),
                  value: 'mermaid',
                  title: context.l10n.exportMermaid,
                  hint: context.l10n.exportMermaidHint,
                ),
                _ExportFormatTile(
                  key: const Key('export-png'),
                  value: 'png',
                  title: context.l10n.exportPng,
                  hint: context.l10n.exportPngHint,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.exportNote,
                  style: context.type.bodySmall!.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (format == 'json') widget.viewModel.exportJson();
      if (format == 'mermaid') {
        widget.viewModel.exportMermaid(title: widget.projectTitle);
      }
      if (format == 'markdown') {
        widget.viewModel.exportMarkdown(title: widget.projectTitle);
      }
      if (format == 'png') await _exportPng();
    } finally {
      _exportOpen = false;
    }
  }

  /// Rasterise the current level: frame it, drop the selection ring, then
  /// composite the transparent board layer onto the theme background.
  Future<void> _exportPng() async {
    final vm = widget.viewModel;
    final node = vm.selectedId;
    final group = vm.selectedGroupId;
    final edge = vm.selectedEdgeId;
    final background = context.colors.background;
    try {
      vm.select(null);
      vm.fitContent();
      // One frame applies the camera request, the next paints it.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('The board is not on screen');
      final size = boundary.size;
      final ratio = (2400 / math.max(size.width, 1)).clamp(1.0, 3.0);
      final layer = await boundary.toImage(pixelRatio: ratio);
      try {
        final bytes = await pngOnBackground(layer, background);
        BrowserPlatform.downloadBytes('foldboard.png', 'image/png', bytes);
      } finally {
        layer.dispose();
      }
    } catch (_) {
      if (mounted) vm.reportExportFailure();
    } finally {
      if (!mounted) {
        // The board left the tree mid-capture; there is no selection to put back.
      } else if (node != null) {
        vm.select(node);
      } else if (group != null) {
        vm.selectGroup(group);
      } else if (edge != null) {
        vm.selectEdge(edge);
      }
    }
  }

  void _openRequests({bool compose = false}) {
    final vm = widget.viewModel;
    if (_requestsOpen) {
      if (compose) {
        _requestsKey.currentState?.startCompose(vm.captureRequestContext());
      }
      return;
    }
    setState(() {
      _detailsOpen = false;
      _requestsOpen = true;
      _requestsCompose = compose ? vm.captureRequestContext() : null;
    });
  }

  void _toggleRequests() => _requestsOpen
      ? _requestsKey.currentState?.requestClose()
      : _openRequests();

  void _returnFocusToRequests() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestsButtonFocus.requestFocus();
    });
  }

  Future<void> _importJson() async {
    if (_importOpen) return;
    _importOpen = true;
    final vm = widget.viewModel;
    try {
      final raw = await widget.pickJson();
      if (raw == null || !mounted) return;
      final document = vm.readImport(raw);
      final revision = vm.repository.revision;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.importTitle),
          content: Text(
            '${context.l10n.importHint}\n\n${context.l10n.block}: ${(document['nodes'] as List).length}\n${context.l10n.fold}: ${(document['groups'] as List).length}\n${context.l10n.arrow}: ${(document['edges'] as List).length}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.importJson),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        if (revision != vm.repository.revision) {
          throw StateError('Board changed during confirmation');
        }
        vm.importDocument(document);
        setState(() => _detailsOpen = false);
      }
    } catch (error) {
      if (mounted) {
        vm.reportImportFailure(error);
      }
    } finally {
      _importOpen = false;
    }
  }

  Future<void> _openShortcuts() async {
    if (_shortcutsOpen) return;
    _shortcutsOpen = true;
    try {
      await KeyboardShortcutsDialog.show(context);
    } finally {
      _shortcutsOpen = false;
      if (mounted) _boardFocus.requestFocus();
    }
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    _searchOpen = true;
    final vm = widget.viewModel;
    final result = await showDialog<BoardSearchResult>(
      context: context,
      builder: (_) => BoardSearchDialog(viewModel: vm),
    );
    _searchOpen = false;
    if (!mounted) return;
    _boardFocus.requestFocus();
    if (result == null) return;
    vm.revealObject(result.id);
    setState(() => _detailsOpen = false);
  }

  @override
  void dispose() {
    _boardFocus.dispose();
    _requestsButtonFocus.dispose();
    super.dispose();
  }

  Future<void> _deleteSelection() async {
    if (!widget.viewModel.canEdit || !WriteAccessScope.canWriteOf(context)) {
      return;
    }
    if (_deleteDialogOpen) return;
    _deleteDialogOpen = true;
    try {
      await confirmDelete(context, widget.viewModel);
    } finally {
      _deleteDialogOpen = false;
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyF &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed) {
      _openSearch();
      return KeyEventResult.handled;
    }
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    final editingText =
        focusedContext?.widget is EditableText ||
        focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null;
    if (editingText) return KeyEventResult.ignored;
    if (_overviewOpen) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _closeOverview();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final vm = widget.viewModel;
    final plain =
        event is KeyDownEvent &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed;
    // While a trace is open it owns the keyboard; see TraceOverlay.
    if (vm.tracing) return KeyEventResult.ignored;
    if (plain && event.logicalKey == LogicalKeyboardKey.keyT) {
      vm.startTraceFromSelection();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        (event.character == '?' ||
            event.logicalKey == LogicalKeyboardKey.question)) {
      _openShortcuts();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        vm.canEdit &&
        WriteAccessScope.canWriteOf(context) &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      if (event.logicalKey == LogicalKeyboardKey.keyZ) {
        keyboard.isShiftPressed ? vm.redo() : vm.undo();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyY) {
        vm.redo();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyD && vm.hasSelection) {
        vm.duplicateSelection();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyC && vm.hasSelection) {
        vm.copySelection();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyV) {
        vm.paste();
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      vm.cancelConnection();
      vm.select(null);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed &&
        vm.hasSelection) {
      if (event is KeyDownEvent) _deleteSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final canEdit = vm.canEdit && WriteAccessScope.canWriteOf(context);
        final storageWarning = vm.repository.storageError != null
            ? vm.warning
            : widget.externalWarning ?? WriteAccessScope.warningOf(context);
        if (_lastLevel != vm.currentLevelId) {
          _detailsOpen = false;
          _lastLevel = vm.currentLevelId;
        }
        if (_wasTracing != vm.tracing) {
          _wasTracing = vm.tracing;
          // A closed trace hands the keyboard back to the board it came from.
          if (!vm.tracing) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _boardFocus.requestFocus();
            });
          }
        }
        // While a connection is open the inspector steps aside: it must not
        // cover the very cards the arrow is aiming for.
        final details =
            _detailsOpen &&
            vm.hasSelection &&
            !vm.hasMultipleSelection &&
            vm.selectedEdge == null &&
            vm.connectFrom == null;
        final wideSelectionActions = constraints.maxWidth >= 1100;
        final traceSelectionLabel = vm.selectedIsReference
            ? context.l10n.traceStraighten
            : vm.selectedEdge != null
            ? context.l10n.traceThrough
            : vm.hasMultipleSelection
            ? context.l10n.traceBetween
            : context.l10n.traceFromHere;
        return Focus(
          focusNode: _boardFocus,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Scaffold(
            body: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    border: Border(
                      bottom: BorderSide(color: context.colors.line),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (vm.currentLevelId != null ||
                          widget.onProjects != null)
                        IconButton(
                          key: Key(
                            vm.currentLevelId == null
                                ? 'back-to-projects'
                                : 'level-up',
                          ),
                          tooltip: vm.currentLevelId == null
                              ? context.l10n.backToProjects
                              : context.l10n.upOneLevel,
                          onPressed: vm.currentLevelId == null
                              ? _leaveProject
                              : () => vm.openLevel(vm.levelPath.last.parentId),
                          icon: const Icon(Icons.arrow_back, size: 20),
                        ),
                      Expanded(
                        child: Text(
                          vm.levelPath.lastOrNull?.title ??
                              widget.projectTitle ??
                              vm.documentTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.titleMedium,
                        ),
                      ),
                      Tooltip(
                        message:
                            storageWarning ??
                            (vm.repository.pendingSave
                                ? context.l10n.saving
                                : context.l10n.savedInBrowser),
                        // "Saving" is motion, not a glyph: a static "…" reads
                        // as nothing and doubles the More-actions icon nearby.
                        child: storageWarning != null
                            ? Icon(
                                Icons.error_outline,
                                color: context.colors.danger,
                                size: 16,
                              )
                            : vm.repository.pendingSave
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: context.colors.muted,
                                ),
                              )
                            : const Icon(Icons.check, size: 16),
                      ),
                      const SizedBox(width: 8),
                      if (!canEdit)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            context.l10n.readOnly,
                            style: context.type.labelSmall,
                          ),
                        ),
                      IconButton(
                        key: const Key('open-overview'),
                        tooltip: context.l10n.overviewTooltip,
                        isSelected: _overviewOpen,
                        onPressed: _overviewOpen
                            ? _closeOverview
                            : _openOverview,
                        selectedIcon: const Icon(Icons.map, size: 20),
                        icon: const Icon(Icons.map_outlined, size: 20),
                      ),
                      if (constraints.maxWidth >= 700)
                        SizedBox(
                          width: 184,
                          height: 34,
                          child: Tooltip(
                            message: context.l10n.findOnBoard,
                            child: OutlinedButton(
                              key: const Key('open-explorer'),
                              onPressed: _openSearch,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.muted,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                side: BorderSide(color: context.colors.line),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusControl,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.search, size: 17),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(context.l10n.search)),
                                  Text(
                                    Theme.of(context).platform ==
                                            TargetPlatform.macOS
                                        ? '⌘ F'
                                        : 'Ctrl F',
                                    style: AppTheme.searchStyle,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        IconButton(
                          key: const Key('open-explorer'),
                          tooltip: context.l10n.findOnBoard,
                          onPressed: _openSearch,
                          icon: const Icon(Icons.search, size: 21),
                        ),
                      IconButton(
                        tooltip: context.l10n.exportProject,
                        onPressed: _openExport,
                        icon: const Icon(
                          Icons.file_download_outlined,
                          size: 20,
                        ),
                      ),
                      PopupMenuButton<String>(
                        key: const Key('board-more'),
                        tooltip: context.l10n.moreActions,
                        icon: const Icon(Icons.more_horiz, size: 20),
                        onSelected: (value) => switch (value) {
                          'import' => _importJson(),
                          'paste' => vm.paste(),
                          'trace' => vm.startTrace(),
                          _ => KeyboardShortcutsDialog.show(context),
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            key: const Key('menu-trace'),
                            value: 'trace',
                            enabled: !_overviewOpen,
                            child: Text(context.l10n.trace),
                          ),
                          PopupMenuItem(
                            key: const Key('menu-paste'),
                            value: 'paste',
                            enabled: !_overviewOpen && canEdit && vm.canPaste,
                            child: Text(context.l10n.paste),
                          ),
                          PopupMenuItem(
                            value: 'import',
                            enabled: !_overviewOpen && canEdit,
                            child: Text(context.l10n.importJson),
                          ),
                          PopupMenuItem(
                            key: const Key('menu-shortcuts'),
                            value: 'shortcuts',
                            child: Text(context.l10n.keyboardShortcuts),
                          ),
                        ],
                      ),
                      IconButton(
                        key: const Key('open-agent-requests'),
                        focusNode: _requestsButtonFocus,
                        tooltip: context.l10n.agentRequests,
                        onPressed: _toggleRequests,
                        icon: Badge(
                          isLabelVisible: vm.requests.pendingCount > 0,
                          label: Text('${vm.requests.pendingCount}'),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            size: 20,
                          ),
                        ),
                      ),
                      // Shortcuts stay reachable via `?`, the More menu and
                      // Settings → About; a fourth entry does not earn a
                      // header slot, least of all on touch screens.
                      const SettingsButton(),
                    ],
                  ),
                ),
                Expanded(
                  key: const ValueKey('planner-board'),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Listener(
                          onPointerDown: (_) => _boardFocus.requestFocus(),
                          child: ArchitectureCanvas(
                            key: ObjectKey(vm),
                            viewModel: vm,
                            captureKey: _captureKey,
                            onOpenDetails: _openDetails,
                            onOpenComments: _openRequests,
                            fitOnStart: true,
                            showGrid:
                                SettingsScope.maybeOf(context)?.showGrid ??
                                true,
                          ),
                        ),
                      ),
                      if (vm.canvasNodes.isEmpty)
                        Center(
                          child: EmptyBoardCard(
                            canEdit: canEdit,
                            onAdd: (process) {
                              process
                                  ? vm.addGroup(title: '')
                                  : vm.addNode(title: '');
                              _openDetails();
                              vm.focusSelection();
                            },
                          ),
                        ),
                      if (vm.hasSelection &&
                          !details &&
                          !_requestsOpen &&
                          !vm.tracing &&
                          vm.connectFrom == null)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 84 + MediaQuery.paddingOf(context).bottom,
                          child: Align(
                            // Follows the dock: both hug the left edge on
                            // narrow screens instead of straddling the width.
                            alignment: constraints.maxWidth < 660
                                ? Alignment.bottomLeft
                                : Alignment.bottomCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: wideSelectionActions
                                    ? math.min(constraints.maxWidth - 32, 1080)
                                    : 520,
                              ),
                              child: Material(
                                key: const Key('selection-summary'),
                                color: context.colors.surfaceHigh,
                                elevation: 6,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusCard,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 12,
                                    right: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          vm.selectionTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (!vm.hasMultipleSelection &&
                                          vm.selectedGroupId != null &&
                                          !vm.selectedIsReference)
                                        if (constraints.maxWidth < 600)
                                          IconButton(
                                            key: const Key(
                                              'enter-selected-process',
                                            ),
                                            tooltip: context.l10n.openFold,
                                            icon: const Icon(
                                              Icons.subdirectory_arrow_right,
                                              size: 18,
                                            ),
                                            onPressed: () => vm.openLevel(
                                              vm.selectedGroupId,
                                            ),
                                          )
                                        else
                                          TextButton(
                                            key: const Key(
                                              'enter-selected-process',
                                            ),
                                            onPressed: () => vm.openLevel(
                                              vm.selectedGroupId,
                                            ),
                                            child: Text(context.l10n.openFold),
                                          ),
                                      if (!vm.hasMultipleSelection &&
                                          vm.selectedEdge == null &&
                                          canEdit)
                                        wideSelectionActions
                                            ? TextButton.icon(
                                                key: const Key(
                                                  'draw-selected-arrow',
                                                ),
                                                onPressed: () =>
                                                    vm.startConnection(
                                                      (vm.selectedId ??
                                                          vm.selectedGroupId)!,
                                                    ),
                                                icon: const Icon(
                                                  Icons.trending_flat,
                                                  size: 20,
                                                ),
                                                label: Text(
                                                  context.l10n.drawArrow,
                                                ),
                                              )
                                            : IconButton(
                                                key: const Key(
                                                  'draw-selected-arrow',
                                                ),
                                                tooltip: context.l10n.drawArrow,
                                                icon: const Icon(
                                                  Icons.trending_flat,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    vm.startConnection(
                                                      (vm.selectedId ??
                                                          vm.selectedGroupId)!,
                                                    ),
                                              ),
                                      if (canEdit && vm.requests.canEdit)
                                        wideSelectionActions
                                            ? TextButton.icon(
                                                key: const Key(
                                                  'comment-selection',
                                                ),
                                                onPressed: () => _openRequests(
                                                  compose: true,
                                                ),
                                                icon: const Icon(
                                                  Icons.add_comment_outlined,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  context.l10n.askAgent,
                                                ),
                                              )
                                            : IconButton(
                                                key: const Key(
                                                  'comment-selection',
                                                ),
                                                tooltip: context.l10n.askAgent,
                                                icon: const Icon(
                                                  Icons.add_comment_outlined,
                                                  size: 18,
                                                ),
                                                onPressed: () => _openRequests(
                                                  compose: true,
                                                ),
                                              ),
                                      if (!vm.hasMultipleSelection &&
                                          vm.selectedIsReference)
                                        IconButton(
                                          tooltip: context.l10n.openOriginal,
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                          ),
                                          onPressed: () => vm.openReference(
                                            (vm.selectedId ??
                                                vm.selectedGroupId)!,
                                          ),
                                        ),
                                      if (vm.selectedEdge != null && canEdit)
                                        PopupMenuButton<String>(
                                          key: const Key('arrow-actions'),
                                          tooltip: context.l10n.moreActions,
                                          onSelected: (_) => _deleteSelection(),
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text(context.l10n.delete),
                                            ),
                                          ],
                                        ),
                                      if (vm.hasMultipleSelection &&
                                          vm.canCopySelection)
                                        IconButton(
                                          key: const Key('copy-selection'),
                                          tooltip: context.l10n.copy,
                                          onPressed: vm.copySelection,
                                          icon: const Icon(
                                            Icons.copy_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      if (vm.hasMultipleSelection && canEdit)
                                        IconButton(
                                          key: const Key('delete-selection'),
                                          tooltip: context.l10n.delete,
                                          onPressed: _deleteSelection,
                                          icon: Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: context.colors.danger,
                                          ),
                                        ),
                                      // The narrowest board keeps the actions
                                      // that change the card; a trace is one
                                      // `T` or one menu item away.
                                      if (constraints.maxWidth >= 400)
                                        wideSelectionActions
                                            ? TextButton.icon(
                                                key: const Key(
                                                  'trace-selection',
                                                ),
                                                onPressed:
                                                    vm.startTraceFromSelection,
                                                icon: const Icon(
                                                  Icons.route,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  traceSelectionLabel,
                                                ),
                                              )
                                            : IconButton(
                                                key: const Key(
                                                  'trace-selection',
                                                ),
                                                tooltip: traceSelectionLabel,
                                                icon: const Icon(
                                                  Icons.route,
                                                  size: 18,
                                                ),
                                                onPressed:
                                                    vm.startTraceFromSelection,
                                              ),
                                      if (!vm.hasMultipleSelection &&
                                          vm.selectedEdge == null)
                                        TextButton(
                                          key: const Key('open-details'),
                                          onPressed: _openDetails,
                                          child: Text(context.l10n.details),
                                        ),
                                      Semantics(
                                        key: const Key('clear-selection'),
                                        button: true,
                                        label: context.l10n.clearSelection,
                                        onTap: () => vm.select(null),
                                        excludeSemantics: true,
                                        child: IconButton(
                                          tooltip: context.l10n.clearSelection,
                                          onPressed: () => vm.select(null),
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        key: const Key('floating-inspector-layer'),
                        child: FloatingInspector(
                          viewModel: vm,
                          visible: details,
                          onClose: () => setState(() => _detailsOpen = false),
                          onAskAgent: () => _openRequests(compose: true),
                        ),
                      ),
                      if (_requestsOpen)
                        Positioned.fill(
                          key: const Key('agent-requests-layer'),
                          child: AgentRequestsPanel(
                            key: _requestsKey,
                            viewModel: vm,
                            composeContext: _requestsCompose,
                            onReturnFocus: _returnFocusToRequests,
                            onClose: () {
                              vm.setCommentDraftTargets(const []);
                              setState(() => _requestsOpen = false);
                            },
                          ),
                        ),
                      if (vm.tracing)
                        Positioned.fill(
                          key: const Key('trace-layer'),
                          child: TraceOverlay(viewModel: vm),
                        ),
                      Positioned(
                        top: 80,
                        left: 16,
                        right: details && constraints.maxWidth >= 700
                            ? 412
                            : 16,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: BoardFeedback(
                            viewModel: vm,
                            externalWarning: widget.externalWarning,
                            externalTicket: widget.externalTicket,
                            onOpenRequests: _openRequests,
                          ),
                        ),
                      ),
                      if (_overviewOpen)
                        Positioned.fill(
                          child: OverviewOverlay(
                            viewModel: vm,
                            onClose: _closeOverview,
                            onOpenLevel: _openOverviewLevel,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
