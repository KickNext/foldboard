import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'transient_feedback.dart';

/// Content scrolls below a stable notification lane. Messages never participate
/// in the content's layout, including while fading out.
class PageFeedback extends StatelessWidget {
  const PageFeedback({
    super.key,
    required this.child,
    required this.message,
    this.ticket,
  });
  final Widget child;
  final String? message;
  final Object? ticket;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(top: 48, child: child),
      Positioned(
        top: 4,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: TransientFeedback(
            message: message,
            ticket: ticket,
            compact: true,
          ),
        ),
      ),
    ],
  );
}

/// Help and persistent error status share a fixed-size app-bar action.
class PageInfoButton extends StatefulWidget {
  const PageInfoButton({
    super.key,
    required this.message,
    this.warning = false,
  });
  final String message;
  final bool warning;
  @override
  State<PageInfoButton> createState() => _PageInfoButtonState();
}

class _PageInfoButtonState extends State<PageInfoButton> {
  final _tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) => Tooltip(
    key: _tooltip,
    message: widget.message,
    child: IconButton(
      onPressed: () => _tooltip.currentState?.ensureTooltipVisible(),
      icon: Icon(
        Icons.info_outline,
        size: 20,
        color: widget.warning ? context.colors.danger : null,
      ),
    ),
  );
}
