import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/app_theme.dart';

class AgentPulse extends StatefulWidget {
  const AgentPulse({
    super.key,
    required this.active,
    required this.version,
    required this.child,
    this.radius = AppTheme.radiusCard,
  });
  final bool active;
  final int version;
  final Widget child;
  final double radius;
  @override
  State<AgentPulse> createState() => _AgentPulseState();
}

class _AgentPulseState extends State<AgentPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: 1,
  );
  @override
  void initState() {
    super.initState();
    if (widget.active) _animation.forward(from: 0);
  }

  @override
  void didUpdateWidget(AgentPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && old.version != widget.version) {
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) {
      final intensity = !widget.active
          ? 0.0
          : MediaQuery.disableAnimationsOf(context)
          ? .6
          : math.sin(math.pi * _animation.value).clamp(0.0, 1.0);
      return DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: context.colors.accent.withValues(alpha: intensity),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: context.colors.accent.withValues(alpha: intensity * .22),
              blurRadius: 18,
              spreadRadius: 4,
            ),
          ],
        ),
        child: child,
      );
    },
  );
}
