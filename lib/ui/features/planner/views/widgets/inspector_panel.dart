import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../../domain/models/architecture_models.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/fold_icon.dart';
import '../../../../core/write_access_scope.dart';

import '../../view_models/planner_view_model.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({
    super.key,
    required this.viewModel,
    required this.node,
    required this.group,
    this.onClose,
    this.onAskAgent,
    this.scrollWhole = false,
  });
  final PlannerViewModel viewModel;
  final ArchitectureNode? node;
  final ArchitectureGroup? group;
  final VoidCallback? onClose;
  final VoidCallback? onAskAgent;
  final bool scrollWhole;
  bool get _isCurrent => node != null
      ? viewModel.selectedId == node!.id
      : group != null && viewModel.selectedGroupId == group!.id;
  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final canEdit = vm.canEdit && WriteAccessScope.canWriteOf(context);
    final node = this.node;
    final group = this.group;
    return Column(
      mainAxisSize: scrollWhole ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: context.colors.accentDark,
                  borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                ),
                child: Center(
                  child: group == null
                      ? Icon(
                          Icons.crop_square_rounded,
                          color: context.colors.accent,
                          size: 18,
                        )
                      : FoldIcon(size: 18, color: context.colors.accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  group != null ? context.l10n.fold : context.l10n.block,
                  style: context.type.titleMedium,
                ),
              ),
              if ((node != null || group != null) && !vm.selectedIsReference)
                PopupMenuButton<String>(
                  enabled: canEdit,
                  key: const Key('move-level'),
                  tooltip: context.l10n.moveTo,
                  icon: const Icon(Icons.drive_file_move_outline, size: 18),
                  onSelected: (id) {
                    if (_isCurrent) vm.moveSelectionTo(id.isEmpty ? null : id);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: '',
                      child: Text(context.l10n.rootLevel),
                    ),
                    for (final target in vm.groups.where(
                      (g) => vm.canParent(g.id),
                    ))
                      PopupMenuItem(
                        value: target.id,
                        child: Text(target.title),
                      ),
                  ],
                ),
              // The selection bar hides while details are open, so the card's
              // Ask agent entry lives here as well.
              if (onAskAgent != null && canEdit && vm.requests.canEdit)
                IconButton(
                  key: const Key('comment-details'),
                  tooltip: context.l10n.askAgent,
                  onPressed: _isCurrent ? onAskAgent : null,
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                ),
              IconButton(
                tooltip: context.l10n.closeDetails,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(height: 1),
        ),
        Flexible(
          fit: scrollWhole ? FlexFit.loose : FlexFit.tight,
          child: ListView(
            shrinkWrap: scrollWhole,
            physics: scrollWhole ? const NeverScrollableScrollPhysics() : null,
            key: ValueKey('inspector-${node?.id ?? group?.id}'),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            children: [
              if (vm.selectedIsReference) ...[
                Text(context.l10n.referenceHint, style: context.type.bodySmall),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    if (_isCurrent) vm.openReference((node?.id ?? group?.id)!);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(context.l10n.openOriginal),
                ),
                const SizedBox(height: 16),
              ],
              if (node != null || group != null) ...[
                _Editor(
                  key: ValueKey('title-${node?.id ?? group!.id}'),
                  readOnly: !canEdit,
                  label: context.l10n.name,
                  value: node?.title ?? group!.title,
                  onChanged: (s) {
                    if (_isCurrent) vm.updateSelected(title: s);
                  },
                ),
                _Editor(
                  key: ValueKey('description-${node?.id ?? group!.id}'),
                  readOnly: !canEdit,
                  label: context.l10n.description,
                  value: node?.description ?? group!.description,
                  lines: 7,
                  onChanged: (s) {
                    if (_isCurrent) vm.updateSelected(description: s);
                  },
                ),
              ],
              if (node != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  key: const Key('connect-node'),
                  onPressed: !canEdit
                      ? null
                      : () {
                          if (!_isCurrent) return;
                          vm.startConnection(node.id);
                          onClose?.call();
                        },
                  icon: const Icon(Icons.trending_flat),
                  label: Text(context.l10n.drawArrow),
                ),
              ],
              if (group != null && !vm.selectedIsReference) ...[
                OutlinedButton.icon(
                  key: const Key('open-process'),
                  onPressed: () {
                    if (_isCurrent) vm.openLevel(group.id);
                  },
                  icon: const Icon(Icons.subdirectory_arrow_right),
                  label: Text(context.l10n.openFold),
                ),
                OutlinedButton.icon(
                  onPressed: !canEdit
                      ? null
                      : () {
                          if (!_isCurrent) return;
                          vm.startConnection(group.id);
                          onClose?.call();
                        },
                  icon: const Icon(Icons.trending_flat),
                  label: Text(context.l10n.drawArrow),
                ),
              ],
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Divider(height: 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          // Wraps instead of overflowing once the panel is narrow.
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 4,
              children: [
                if (!vm.selectedIsReference)
                  TextButton.icon(
                    key: const Key('duplicate-inspector'),
                    onPressed: !canEdit
                        ? null
                        : () {
                            if (_isCurrent) vm.duplicateSelection();
                          },
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: Text(context.l10n.duplicate),
                  ),
                TextButton.icon(
                  key: const Key('delete-inspector'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.danger,
                  ),
                  onPressed: !canEdit
                      ? null
                      : () {
                          if (_isCurrent) confirmDelete(context, vm);
                        },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(
                    vm.selectedIsReference
                        ? context.l10n.disconnect
                        : context.l10n.delete,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> confirmDelete(BuildContext context, PlannerViewModel vm) async {
  if (!vm.canEdit || !WriteAccessScope.canWriteOf(context)) return;
  if (!vm.hasSelection) return;
  final connectionIds = vm.selectedConnectionIds.toSet();
  final cardIds = vm.selectedCardIds;
  final multiple = vm.hasMultipleSelection;
  final reference = vm.selectedIsReference;
  final referenceIds = vm.referenceConnectionIds.toSet();
  final id = vm.selectedId ?? vm.selectedGroupId ?? vm.selectedEdgeId;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        reference
            ? context.l10n.disconnect
            : context.l10n.deleteTitle(vm.selectionTitle),
      ),
      content: Text(
        multiple
            ? context.l10n.deleteSelectedCardsMessage
            : reference
            ? context.l10n.disconnectHint
            : vm.selectedGroup != null
            ? context.l10n.deleteFoldMessage
            : vm.selectedNode != null
            ? context.l10n.deleteBlockMessage
            : vm.selectedConnectionIds.length > 1
            ? context.l10n.deleteConnections(vm.selectedConnectionIds.length)
            : context.l10n.deleteArrowMessage,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            reference ? context.l10n.disconnect : context.l10n.delete,
          ),
        ),
      ],
    ),
  );
  // Do not delete a different object if an agent changes selection while the dialog is open.
  if (confirmed == true &&
      setEquals(cardIds, vm.selectedCardIds) &&
      reference == vm.selectedIsReference &&
      (!reference ||
          (referenceIds.length == vm.referenceConnectionIds.length &&
              vm.referenceConnectionIds.every(referenceIds.contains))) &&
      connectionIds.length == vm.selectedConnectionIds.length &&
      vm.selectedConnectionIds.every(connectionIds.contains) &&
      id == (vm.selectedId ?? vm.selectedGroupId ?? vm.selectedEdgeId)) {
    vm.deleteSelected();
  }
}

class _Editor extends StatefulWidget {
  const _Editor({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.lines = 1,
    this.readOnly = false,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final int lines;
  final bool readOnly;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focusNode = FocusNode(
    debugLabel: widget.lines == 1 ? 'Inspector name' : 'Inspector description',
  );

  @override
  void initState() {
    super.initState();
    if (widget.lines == 1 && widget.value.isEmpty && !widget.readOnly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: context.type.labelMedium!.copyWith(
            color: context.colors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label: widget.label,
          child: TextField(
            autofocus:
                widget.lines == 1 && widget.value.isEmpty && !widget.readOnly,
            focusNode: _focusNode,
            readOnly: widget.readOnly,
            controller: _controller,
            maxLines: widget.lines,
            style: widget.lines == 1
                ? AppTheme.inspectorTitle.copyWith(color: context.colors.text)
                : context.type.bodyMedium,
            decoration: AppTheme.inspectorInput(
              context,
              title: widget.lines == 1,
            ),
            onChanged: widget.onChanged,
          ),
        ),
      ],
    ),
  );
}
