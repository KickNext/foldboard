import 'package:flutter/material.dart';

import 'app_theme.dart';

/// A row of mutually exclusive options, shown in full.
///
/// Preferred over a dropdown for short, stable option sets: the choices stay
/// readable without opening a menu, and nothing about it reads as Material.
class SegmentedPicker<T> extends StatelessWidget {
  const SegmentedPicker({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<(T value, String label)> options;

  /// `null` disables the whole control.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final enabled = onChanged != null;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl + 3),
        border: Border.all(color: p.line),
      ),
      // Wraps rather than overflowing when the page is narrow.
      child: Wrap(
        runSpacing: 3,
        children: [
          for (final (option, label) in options)
            _Segment(
              label: label,
              selected: option == value,
              onTap: enabled && option != value
                  ? () => onChanged!(option)
                  : null,
              dimmed: !enabled,
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.dimmed,
  });
  final String label;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final selected = widget.selected;
    return Semantics(
      button: true,
      selected: selected,
      label: widget.label,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected
                  ? p.surface
                  : _hovered && widget.onTap != null
                  ? p.text.withValues(alpha: .05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: selected ? p.line : Colors.transparent),
            ),
            child: Text(
              widget.label,
              style: context.type.labelLarge!.copyWith(
                color: widget.dimmed
                    ? p.muted.withValues(alpha: .55)
                    : selected
                    ? p.text
                    : p.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
