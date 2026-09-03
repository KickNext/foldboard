import 'package:flutter/material.dart';

import '../../../../../l10n/l10n.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/fold_icon.dart';

/// Shown in place of an empty level. It names the two primitives instead of
/// pointing at a button, so the board explains itself before the first card.
class EmptyBoardCard extends StatelessWidget {
  const EmptyBoardCard({super.key, required this.canEdit, required this.onAdd});

  /// `true` creates a process, `false` a block.
  final ValueChanged<bool> onAdd;
  final bool canEdit;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 380),
    child: DecoratedBox(
      key: const Key('empty-board'),
      decoration: AppTheme.floatingPanel(context)
          .copyWith(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.emptyBoardTitle,
                style: context.type.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.emptyBoardBody,
                style: context.type.bodySmall!.copyWith(
                  color: context.colors.muted,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      key: const Key('empty-add-block'),
                      onPressed: () => onAdd(false),
                      icon: const Icon(Icons.add_box_outlined, size: 18),
                      label: Text(context.l10n.addBlock),
                    ),
                    OutlinedButton.icon(
                      key: const Key('empty-add-process'),
                      onPressed: () => onAdd(true),
                      icon: const FoldIcon(size: 18, add: true),
                      label: Text(context.l10n.addFold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.emptyBoardAgentHint,
                  style: context.type.labelSmall!.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
