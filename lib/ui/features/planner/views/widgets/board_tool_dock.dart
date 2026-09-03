import 'package:flutter/material.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../core/app_theme.dart';
import '../../../../core/fold_icon.dart';
import '../../../../core/write_access_scope.dart';
import '../../view_models/planner_view_model.dart';

/// Canvas modes and creation only. Layout commands live with the view controls;
/// agent requests have a single entry in the header.
class BoardToolDock extends StatelessWidget {
  const BoardToolDock({
    super.key,
    required this.viewModel,
    required this.onAdd,
    this.showLabels = false,
  });
  final PlannerViewModel viewModel;
  final ValueChanged<String> onAdd;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final writable = vm.canEdit && WriteAccessScope.canWriteOf(context);
    Widget mode(CanvasTool value, IconData icon, String label) {
      final selected = vm.canvasTool == value;
      return SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          key: ValueKey('tool-${value.name}'),
          tooltip: label,
          isSelected: selected,
          style: IconButton.styleFrom(
            backgroundColor: selected
                ? context.colors.accentDark
                : Colors.transparent,
            foregroundColor: selected
                ? context.colors.accent
                : context.colors.muted,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            ),
          ),
          onPressed: () => vm.setCanvasTool(value),
          icon: Icon(icon, size: 20),
        ),
      );
    }

    Widget add(String type, Key key, Widget icon, String label) {
      final onPressed = writable ? () => onAdd(type) : null;
      if (showLabels) {
        return Tooltip(
          message: label,
          child: TextButton.icon(
            key: key,
            onPressed: onPressed,
            icon: icon,
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.text,
              disabledForegroundColor: context.colors.muted.withValues(
                alpha: .55,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 40),
            ),
          ),
        );
      }
      return SizedBox(
        width: 40,
        height: 40,
        child: IconButton(
          key: key,
          tooltip: label,
          onPressed: onPressed,
          icon: icon,
        ),
      );
    }

    return Semantics(
      container: true,
      label: context.l10n.boardTools,
      child: DecoratedBox(
        key: const Key('board-tool-dock'),
        decoration: AppTheme.floatingPanel(context)
            .copyWith(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                mode(
                  CanvasTool.select,
                  Icons.near_me_outlined,
                  context.l10n.selectAndMove,
                ),
                mode(
                  CanvasTool.pan,
                  Icons.pan_tool_outlined,
                  context.l10n.panAnywhere,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    height: 22,
                    width: 1,
                    child: ColoredBox(color: context.colors.line),
                  ),
                ),
                add(
                  'node',
                  const Key('add-block'),
                  const Icon(Icons.add_box_outlined, size: 20),
                  context.l10n.addBlock,
                ),
                add(
                  'group',
                  const Key('add-process'),
                  const FoldIcon(size: 20, add: true),
                  context.l10n.addFold,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The path only names the current level. Keeping commands out of this surface
/// lets deep paths use the whole width and preserves navigation hierarchy.
class LevelPathBar extends StatelessWidget {
  const LevelPathBar({super.key, required this.viewModel});
  final PlannerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return DecoratedBox(
      key: const Key('level-path'),
      decoration: AppTheme.floatingPanel(context),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // The deepest level stays visible when the path overflows.
                  reverse: true,
                  child: Row(
                    children: [
                      TextButton(
                        key: const Key('level-root'),
                        onPressed: vm.currentLevelId == null
                            ? null
                            : () => vm.openLevel(null),
                        child: Text(context.l10n.rootLevel),
                      ),
                      for (final level in vm.levelPath) ...[
                        const Icon(Icons.chevron_right, size: 14),
                        TextButton(
                          onPressed: () => vm.openLevel(level.id),
                          child: Text(level.title),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Always-visible history controls, anchored at the top-left of the canvas.
class BoardHistoryControls extends StatelessWidget {
  const BoardHistoryControls({super.key, required this.viewModel});
  final PlannerViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final writable = vm.canEdit && WriteAccessScope.canWriteOf(context);
    final command = Theme.of(context).platform == TargetPlatform.macOS
        ? '⌘'
        : 'Ctrl';
    return Semantics(
      container: true,
      label: context.l10n.history,
      child: DecoratedBox(
        key: const Key('board-history'),
        decoration: AppTheme.floatingPanel(context),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('undo'),
                  tooltip: '${context.l10n.undo} ($command Z)',
                  onPressed: writable && vm.repository.canUndo ? vm.undo : null,
                  icon: const Icon(Icons.undo, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  key: const Key('redo'),
                  tooltip: '${context.l10n.redo} ($command Shift Z)',
                  onPressed: writable && vm.repository.canRedo ? vm.redo : null,
                  icon: const Icon(Icons.redo, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
