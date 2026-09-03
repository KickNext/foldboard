import 'dart:async';

import 'package:flutter/material.dart';
import 'package:foldboard/l10n/l10n.dart';

import 'app_theme.dart';

/// Transient feedback in a reserved UI lane, independent of the camera.
class TransientFeedback extends StatefulWidget {
  const TransientFeedback({
    super.key,
    required this.message,
    this.warning = true,
    this.ticket,
    this.onDismiss,
    this.onExpired,
    this.duration = const Duration(seconds: 4),
    this.compact = false,
    this.actionLabel,
    this.onAction,
    this.dismissLabel,
    this.surfaceKey = const Key('feedback'),
    this.dismissKey = const Key('dismiss-feedback'),
  });
  final String? message;
  final bool warning;
  final Object? ticket;
  final VoidCallback? onDismiss;
  final VoidCallback? onExpired;
  final Duration? duration;
  final bool compact;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? dismissLabel;
  final Key surfaceKey;
  final Key dismissKey;

  @override
  State<TransientFeedback> createState() => _TransientFeedbackState();
}

class _TransientFeedbackState extends State<TransientFeedback> {
  Timer? _timer;
  Object? _ticket;
  String? _message;
  bool _warning = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TransientFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final ticket = (widget.message, widget.ticket, widget.duration);
    if (ticket == _ticket) return;
    _ticket = ticket;
    _timer?.cancel();
    final message = widget.message;
    _visible = message != null;
    if (message != null) {
      _message = message;
      _warning = widget.warning;
      if (widget.duration case final duration?) {
        _timer = Timer(duration, () {
          _hide();
          widget.onExpired?.call();
        });
      }
    }
  }

  void _hide() {
    _timer?.cancel();
    if (mounted) setState(() => _visible = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !_visible,
    child: ExcludeSemantics(
      excluding: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        onEnd: () {
          if (!_visible && _message != null) setState(() => _message = null);
        },
        child: _message == null
            ? const SizedBox.shrink()
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: widget.compact ? 40 : 76,
                ),
                child: Material(
                  key: widget.surfaceKey,
                  color: context.colors.surfaceHigh,
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: .24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    side: BorderSide(
                      color: _warning
                          ? context.colors.danger.withValues(alpha: .5)
                          : context.colors.line,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _warning ? Icons.info_outline : Icons.trending_flat,
                          size: 20,
                          color: _warning
                              ? context.colors.danger
                              : context.colors.accent,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Semantics(
                            liveRegion: true,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: widget.compact ? 8 : 12,
                              ),
                              child: Tooltip(
                                message: _message!,
                                child: Text(
                                  _message!,
                                  maxLines: widget.compact ? 1 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.type.bodySmall!.copyWith(
                                    color: context.colors.text,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.actionLabel != null)
                          TextButton(
                            onPressed: widget.onAction,
                            child: Text(widget.actionLabel!),
                          ),
                        IconButton(
                          constraints: widget.compact
                              ? const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                )
                              : null,
                          key: widget.dismissKey,
                          tooltip: widget.dismissLabel ?? context.l10n.close,
                          onPressed: () {
                            _hide();
                            widget.onDismiss?.call();
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}
