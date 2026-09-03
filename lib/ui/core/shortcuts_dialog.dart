import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'app_theme.dart';

/// One reference for every board shortcut. Reached from the board with `?`,
/// from More actions, and from Settings → About.
class KeyboardShortcutsDialog extends StatefulWidget {
  const KeyboardShortcutsDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const KeyboardShortcutsDialog(),
  );

  @override
  State<KeyboardShortcutsDialog> createState() =>
      _KeyboardShortcutsDialogState();
}

class _KeyboardShortcutsDialogState extends State<KeyboardShortcutsDialog> {
  // The list is taller than the dialog; a thumb that is always on screen is
  // the only hint that more groups follow.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final apple = switch (Theme.of(context).platform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
    final mod = apple ? '⌘' : 'Ctrl';
    final groups = <String, List<(List<String>, String)>>{
      l10n.shortcutsBoard: [
        ([mod, 'F'], l10n.shortcutSearch),
        (['Space', '+ ${l10n.keyDrag}'], l10n.shortcutPan),
        ([l10n.keyMiddleMouse], l10n.shortcutPan),
        ([l10n.keyTwoFingerScroll], l10n.shortcutPan),
        ([l10n.keyPinch], l10n.shortcutZoom),
        ([mod, '+ ${l10n.keyWheel}'], l10n.shortcutZoom),
        (['?'], l10n.shortcutHelp),
      ],
      l10n.shortcutsEditing: [
        ([l10n.keyDrag], l10n.shortcutMarquee),
        ([mod, 'Z'], l10n.undo),
        ([mod, 'Shift', 'Z'], l10n.redo),
        ([mod, 'D'], l10n.shortcutDuplicate),
        ([mod, 'C'], l10n.shortcutCopy),
        ([mod, 'V'], l10n.shortcutPaste),
        (['Delete'], l10n.shortcutDelete),
        (['Esc'], l10n.shortcutEscape),
      ],
      l10n.shortcutsNavigation: [
        (['Tab'], l10n.shortcutFocusCard),
        (['Enter'], l10n.shortcutOpen),
        ([l10n.keyArrows], l10n.shortcutMove),
        (['Shift', l10n.keyArrows], l10n.shortcutMoveFar),
      ],
      l10n.shortcutsTrace: [
        (['T'], l10n.shortcutTrace),
        (['←', '→'], l10n.shortcutTraceStep),
        (['[', ']'], l10n.shortcutTraceBranch),
        (['Enter'], l10n.shortcutTraceOpen),
        (['1', '2'], l10n.shortcutTraceDensity),
        (['Esc'], l10n.traceClose),
      ],
    };
    return AlertDialog(
      key: const Key('keyboard-shortcuts-dialog'),
      title: Text(l10n.keyboardShortcuts),
      content: SizedBox(
        width: 460,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.keyboardShortcutsHint,
                  style: context.type.bodySmall!.copyWith(
                    color: context.colors.muted,
                  ),
                ),
                for (final group in groups.entries) ...[
                  const SizedBox(height: 20),
                  Text(
                    group.key,
                    style: context.type.labelMedium!.copyWith(
                      color: context.colors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final (keys, label) in group.value)
                    _ShortcutRow(keys: keys, label: label),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.keys, required this.label});
  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [for (final key in keys) _KeyCap(key)],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(label, style: context.type.bodySmall),
          ),
        ),
      ],
    ),
  );
}

class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    // A legend without a border reads as prose; give it a physical key edge.
    final decorated = !label.startsWith('+');
    return Container(
      padding: decorated
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
          : const EdgeInsets.only(top: 3),
      decoration: decorated
          ? BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(color: context.colors.line),
            )
          : null,
      child: Text(
        label,
        style: context.type.labelSmall!.copyWith(
          color: decorated ? context.colors.text : context.colors.muted,
          fontWeight: decorated ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
