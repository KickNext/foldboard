import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../../domain/models/board_request.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/write_access_scope.dart';
import '../../view_models/planner_view_model.dart';

/// A floating, non-modal panel: the board stays visible and interactive while
/// a request is written or read, so a target can be checked without closing.
/// Compose context is captured when composing starts, never silently later.
class AgentRequestsPanel extends StatefulWidget {
  const AgentRequestsPanel({
    super.key,
    required this.viewModel,
    required this.onClose,
    this.onReturnFocus,
    this.composeContext,
  });
  final PlannerViewModel viewModel;
  final VoidCallback onClose;
  final VoidCallback? onReturnFocus;
  final Map<String, dynamic>? composeContext;
  @override
  State<AgentRequestsPanel> createState() => AgentRequestsPanelState();
}

class AgentRequestsPanelState extends State<AgentRequestsPanel> {
  final _text = TextEditingController();
  final _textFocus = FocusNode(debugLabel: 'Agent request text');
  final _newRequestFocus = FocusNode(debugLabel: 'Ask agent');
  late Map<String, dynamic>? _composeContext = widget.composeContext;
  String _status = 'pending';
  String? _error;
  bool _saving = false;
  bool get hasDraft => _text.text.trim().isNotEmpty;
  bool get _writable =>
      widget.viewModel.canEdit &&
      widget.viewModel.requests.canEdit &&
      WriteAccessScope.canWriteOf(context);

  @override
  void initState() {
    super.initState();
    widget.viewModel.hasRequestDraft = () => hasDraft;
    // Highlight the draft's anchor cards; deferred past the current build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _publishDraftTargets();
      (_composeContext == null ? _newRequestFocus : _textFocus).requestFocus();
    });
  }

  @override
  void dispose() {
    widget.viewModel.hasRequestDraft = null;
    _text.dispose();
    _textFocus.dispose();
    _newRequestFocus.dispose();
    super.dispose();
  }

  void _focusAfterBuild(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _publishDraftTargets() {
    widget.viewModel.setCommentDraftTargets([
      for (final target
          in (_composeContext?['targets'] as List? ?? const []).cast<Map>())
        target['id'] as String,
    ]);
  }

  /// Re-captures context: composing always targets the current selection.
  void startCompose(Map<String, dynamic> captured) {
    if (_composeContext != null) return; // Keep the existing draft's target.
    setState(() => _composeContext = captured);
    _publishDraftTargets();
    _focusAfterBuild(_textFocus);
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.discardRequest),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.discard),
          ),
        ],
      ),
    );
    return discard == true && mounted;
  }

  Future<bool> prepareToLeave() async {
    if (hasDraft && !await _confirmDiscard()) return false;
    if (!mounted) return false;
    _text.clear();
    return true;
  }

  Future<bool> requestClose({bool returnFocus = true}) async {
    if (!await prepareToLeave()) return false;
    widget.onClose();
    if (returnFocus) widget.onReturnFocus?.call();
    return true;
  }

  Future<void> _cancelCompose() async {
    if (hasDraft && !await _confirmDiscard()) return;
    _text.clear();
    setState(() => _composeContext = null);
    _publishDraftTargets();
    _focusAfterBuild(_newRequestFocus);
  }

  void _save() {
    final captured = _composeContext;
    if (!_writable || _saving || !hasDraft || captured == null) return;
    _saving = true;
    try {
      widget.viewModel.requests.add(_text.text, captured);
      _text.clear();
      setState(() {
        _composeContext = null;
        _status = 'pending';
        _error = null;
      });
      _publishDraftTargets();
      _focusAfterBuild(_newRequestFocus);
    } catch (_) {
      setState(() => _error = context.l10n.requestSaveFailed);
    } finally {
      _saving = false;
    }
  }

  Future<void> _remove(BoardRequest item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.removeRequest),
        content: Text(context.l10n.removeRequestHint),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    _run(() => widget.viewModel.requests.remove(item.id));
  }

  void _run(VoidCallback action) {
    try {
      action();
      setState(() => _error = null);
    } catch (_) {
      setState(() => _error = context.l10n.requestSaveFailed);
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_composeContext != null) {
      unawaited(_cancelCompose());
    } else {
      unawaited(requestClose());
    }
    return KeyEventResult.handled;
  }

  Widget _keyboardScope(Widget child) => FocusTraversalGroup(
    child: Focus(skipTraversal: true, onKeyEvent: _handleKey, child: child),
  );

  Widget _target(Map<String, dynamic> target) {
    final vm = widget.viewModel;
    final id = target['id'] as String;
    final exists =
        vm.nodes.any((e) => e.id == id) ||
        vm.groups.any((e) => e.id == id) ||
        vm.edges.any((e) => e.id == id);
    final title = target['title'] as String;
    return TextButton.icon(
      // The panel stays open: revealing a target is a glance, not a switch.
      onPressed: exists && target['type'] != 'edge'
          ? () => vm.revealObject(id)
          : null,
      icon: Icon(exists ? Icons.crop_square_rounded : Icons.link_off, size: 14),
      label: Text(
        exists ? title : context.l10n.requestTargetRemoved(title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _request(BoardRequest item) => Container(
    key: ValueKey('request-${item.id}'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surfaceHigh,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      border: Border.all(color: context.colors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              item.status == 'handled'
                  ? Icons.task_alt
                  : Icons.chat_bubble_outline,
              size: 16,
              color: context.colors.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.context['levelTitle'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.labelMedium,
              ),
            ),
            if (_writable)
              PopupMenuButton<String>(
                key: ValueKey('request-menu-${item.id}'),
                tooltip: context.l10n.moreActions,
                onSelected: (value) => value == 'remove'
                    ? _remove(item)
                    : _run(() => widget.viewModel.requests.reopen(item.id)),
                itemBuilder: (_) => [
                  if (item.status == 'handled')
                    PopupMenuItem(
                      value: 'reopen',
                      child: Text(context.l10n.reopenRequest),
                    ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(context.l10n.removeRequest),
                  ),
                ],
              ),
          ],
        ),
        for (final target in item.targets) _target(target),
        const SizedBox(height: 8),
        SelectableText(item.text, style: context.type.bodyMedium),
        if (item.response != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Text(
            context.l10n.agentResponse,
            style: context.type.labelMedium!.copyWith(
              color: context.colors.accent,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(item.response!, style: context.type.bodyMedium),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.viewModel,
    builder: (context, _) {
      final vm = widget.viewModel;
      final compose = _composeContext != null;
      final items = vm.requests.items
          .where((e) => e.status == _status)
          .toList()
          .reversed
          .toList();
      final capturedTargets = (_composeContext?['targets'] as List? ?? const [])
          .cast<Map>();
      final targetTitle = capturedTargets.isEmpty
          ? (_composeContext?['levelTitle'] as String? ?? '')
          : capturedTargets.map((e) => e['title']).join(', ');
      return _keyboardScope(
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final margin = compact ? 12.0 : 16.0;
            final clearance = 76.0 + MediaQuery.paddingOf(context).bottom;
            return Padding(
              padding: EdgeInsets.fromLTRB(margin, margin, margin, clearance),
              child: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: math.min(400, constraints.maxWidth - margin * 2),
                  height: math.max(
                    0,
                    constraints.maxHeight - margin - clearance,
                  ),
                  child: DecoratedBox(
                    key: const Key('requests-surface'),
                    decoration: AppTheme.floatingPanel(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusFloating,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      compose
                                          ? context.l10n.askAgent
                                          : context.l10n.agentRequests,
                                      style: context.type.titleLarge,
                                    ),
                                  ),
                                  IconButton(
                                    key: const Key('close-agent-requests'),
                                    onPressed: requestClose,
                                    tooltip: context.l10n.close,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, bodyConstraints) =>
                                      SingleChildScrollView(
                                        key: const Key('requests-body-scroll'),
                                        child: SizedBox(
                                          height: math.max(
                                            320,
                                            bodyConstraints.maxHeight,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                context.l10n.agentRequestsHint,
                                                style: context.type.bodySmall!
                                                    .copyWith(
                                                      color:
                                                          context.colors.muted,
                                                    ),
                                              ),
                                              const SizedBox(height: 16),
                                              if (compose) ...[
                                                Text(
                                                  context.l10n.requestAbout(
                                                    targetTitle,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      context.type.labelLarge,
                                                ),
                                                const SizedBox(height: 12),
                                                Expanded(
                                                  child: TextField(
                                                    key: const Key(
                                                      'request-text',
                                                    ),
                                                    controller: _text,
                                                    focusNode: _textFocus,
                                                    readOnly: !_writable,
                                                    maxLength: 4000,
                                                    maxLines: null,
                                                    expands: true,
                                                    textAlignVertical:
                                                        TextAlignVertical.top,
                                                    decoration: InputDecoration(
                                                      labelText: context
                                                          .l10n
                                                          .requestQuestion,
                                                      alignLabelWithHint: true,
                                                      hintText: context
                                                          .l10n
                                                          .requestQuestionHint,
                                                    ),
                                                    onChanged: (_) =>
                                                        setState(() {}),
                                                  ),
                                                ),
                                              ] else ...[
                                                SegmentedButton<String>(
                                                  // A check on "Pending" reads
                                                  // as "handled"; the fill
                                                  // marks the choice alone.
                                                  showSelectedIcon: false,
                                                  segments: [
                                                    ButtonSegment(
                                                      value: 'pending',
                                                      label: Text(
                                                        context.l10n
                                                            .pendingRequests(
                                                              vm
                                                                  .requests
                                                                  .pendingCount,
                                                            ),
                                                      ),
                                                    ),
                                                    ButtonSegment(
                                                      value: 'handled',
                                                      label: Text(
                                                        context
                                                            .l10n
                                                            .handledRequests,
                                                      ),
                                                    ),
                                                  ],
                                                  selected: {_status},
                                                  onSelectionChanged:
                                                      (values) => setState(
                                                        () => _status =
                                                            values.single,
                                                      ),
                                                ),
                                                const SizedBox(height: 12),
                                                Expanded(
                                                  child: vm.requests.loadFailed
                                                      ? Center(
                                                          child: Text(
                                                            context
                                                                .l10n
                                                                .requestLoadFailed,
                                                          ),
                                                        )
                                                      : items.isEmpty
                                                      ? Center(
                                                          child: Text(
                                                            context
                                                                .l10n
                                                                .noRequests,
                                                          ),
                                                        )
                                                      : ListView.builder(
                                                          key: const Key(
                                                            'requests-list',
                                                          ),
                                                          itemCount:
                                                              items.length,
                                                          itemBuilder:
                                                              (
                                                                _,
                                                                index,
                                                              ) => _request(
                                                                items[index],
                                                              ),
                                                        ),
                                                ),
                                              ],
                                              SizedBox(
                                                height: 48,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    _error ??
                                                        (vm.requests.conflict
                                                            ? context
                                                                  .l10n
                                                                  .storageConflict
                                                            : !_writable
                                                            ? context
                                                                  .l10n
                                                                  .readOnly
                                                            : ''),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: context
                                                        .type
                                                        .bodySmall!
                                                        .copyWith(
                                                          color: context
                                                              .colors
                                                              .danger,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (compose)
                                    TextButton(
                                      onPressed: _cancelCompose,
                                      child: Text(context.l10n.cancel),
                                    ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    key: Key(
                                      compose ? 'save-request' : 'new-request',
                                    ),
                                    focusNode: compose
                                        ? null
                                        : _newRequestFocus,
                                    onPressed:
                                        !_writable || (compose && !hasDraft)
                                        ? null
                                        : compose
                                        ? _save
                                        : () => startCompose(
                                            vm.captureRequestContext(),
                                          ),
                                    icon: Icon(
                                      compose ? Icons.check : Icons.add,
                                      size: 18,
                                    ),
                                    label: Text(
                                      compose
                                          ? context.l10n.saveRequest
                                          : context.l10n.askAgent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
