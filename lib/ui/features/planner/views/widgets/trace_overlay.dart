import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:foldboard/l10n/l10n.dart';

import '../../../../../domain/use_cases/trace_path.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/segmented_picker.dart';
import '../../../../core/write_access_scope.dart';
import '../../view_models/board_search_result.dart';
import '../../view_models/planner_view_model.dart';
import 'board_search_dialog.dart';

const _cardWidth = 260.0;
const _cardHeight = 118.0;
const _gap = 44.0;
const _stride = _cardWidth + _gap;
const _bandHeight = 26.0;
const _bandGap = 6.0;
const _chipHeight = 24.0;
const _railHeight = 74.0;
const _stagePadding = 32.0;

/// The straightened thread, laid over the board it was read from.
///
/// A lens, not an editor of structure: it reads the same document, leaves the
/// level underneath exactly where it was, and hands every step back to the
/// board in one gesture.
class TraceOverlay extends StatefulWidget {
  const TraceOverlay({super.key, required this.viewModel});

  final PlannerViewModel viewModel;

  @override
  State<TraceOverlay> createState() => _TraceOverlayState();
}

class _TraceOverlayState extends State<TraceOverlay> {
  final _strip = ScrollController();
  // The board is still mounted under the trace, and its cards answer to the
  // arrow keys. The trace holds the keyboard while it is open so a walk along
  // the thread can never move a card underneath instead.
  final _keys = FocusNode(debugLabel: 'Trace');
  int _lastVersion = -1;
  int _lastFocus = -1;

  @override
  void initState() {
    super.initState();
    // Taking the keyboard, not merely asking for it: the board or one of its
    // cards already holds focus when a trace opens, so autofocus would pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keys.requestFocus();
    });
  }

  @override
  void dispose() {
    _strip.dispose();
    _keys.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    final vm = widget.viewModel;
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyDownEvent ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      vm.exitTrace();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      vm.stepTrace(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      vm.stepTrace(-1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final step = vm.focusedTraceItem;
      if (step == null) return KeyEventResult.handled;
      step.isCollapsedFold
          ? vm.expandTraceFold(step.id)
          : vm.openTraceStep(step.id);
    } else if (key == LogicalKeyboardKey.bracketLeft ||
        key == LogicalKeyboardKey.bracketRight) {
      vm.traceBranchAtFocus();
    } else if (key == LogicalKeyboardKey.digit1) {
      vm.setTraceDensity(TraceDensity.cards);
    } else if (key == LogicalKeyboardKey.digit2) {
      vm.setTraceDensity(TraceDensity.read);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _keepFocusVisible(List<TraceItem> items, {required bool jump}) {
    final vm = widget.viewModel;
    final index = items.indexWhere((item) => item.covers(vm.traceFocus));
    if (index < 0 ||
        !_strip.hasClients ||
        !_strip.position.hasContentDimensions) {
      return;
    }
    final viewport = _strip.position.viewportDimension;
    final left = index * _stride;
    final target = (left - (viewport - _cardWidth) / 2).clamp(
      0.0,
      _strip.position.maxScrollExtent,
    );
    if ((target - _strip.offset).abs() < 1) return;
    jump
        ? _strip.jumpTo(target)
        : _strip.animateTo(
            target,
            duration: AppTheme.panelSwap,
            curve: AppTheme.portalCurve,
          );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final trace = vm.trace;
    if (trace == null) return const SizedBox.shrink();
    final items = vm.traceItems;
    final fresh = _lastVersion != vm.traceVersion;
    if (fresh || _lastFocus != vm.traceFocus) {
      _lastVersion = vm.traceVersion;
      _lastFocus = vm.traceFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keepFocusVisible(items, jump: fresh);
      });
    }
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      // A Listener, not a GestureDetector: it blocks the board underneath and
      // takes the keyboard back without ever entering the gesture arena, where
      // it would contest taps with the controls it wraps.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _keys.requestFocus(),
        // Opaque: the board keeps its place underneath, but a card of it showing
        // through the thread would read as part of the thread.
        child: ColoredBox(
          key: const Key('trace-overlay'),
          color: context.colors.background,
          child: LayoutBuilder(
            builder: (context, box) => Column(
              children: [
                _TraceBar(viewModel: vm, trace: trace, keyboard: _keys),
                Expanded(
                  child: vm.traceDensity == TraceDensity.read
                      ? _TraceRead(viewModel: vm, trace: trace)
                      : _TraceStrip(
                          viewModel: vm,
                          trace: trace,
                          items: items,
                          controller: _strip,
                        ),
                ),
                // A short window spends its height on the thread itself.
                if (vm.traceDensity == TraceDensity.cards &&
                    box.maxHeight >= 420)
                  _TraceRail(viewModel: vm, items: items, controller: _strip),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TraceBar extends StatelessWidget {
  const _TraceBar({
    required this.viewModel,
    required this.trace,
    required this.keyboard,
  });

  final PlannerViewModel viewModel;
  final Trace trace;
  final FocusNode keyboard;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    final l10n = context.l10n;
    final first = trace.steps.first;
    final last = trace.steps.last;
    String name(TraceStep step) => step.title.isEmpty
        ? (step.isFold ? l10n.newFold : l10n.newBlock)
        : step.title;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(bottom: BorderSide(color: context.colors.line)),
      ),
      child: Row(
        children: [
          // Both ends are controls: the thread runs from wherever the arrows
          // start to wherever they stop until you say otherwise, and saying so
          // searches the whole board, not the level that happens to be open.
          // The ends get the room first: a truncated card name costs more than
          // a truncated step count.
          Expanded(
            flex: 4,
            child: Semantics(
              label: l10n.traceEnds(name(first), name(last)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _Endpoint(
                      viewModel: vm,
                      keyboard: keyboard,
                      start: true,
                      label: name(first),
                      pinned: vm.tracePinnedFrom != null,
                    ),
                  ),
                  Text(
                    '→',
                    style: context.type.titleMedium!.copyWith(
                      color: context.colors.accent,
                    ),
                  ),
                  Flexible(
                    child: _Endpoint(
                      viewModel: vm,
                      keyboard: keyboard,
                      start: false,
                      label: name(last),
                      pinned: vm.tracePinnedTo != null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              '${l10n.traceStepCount(trace.steps.length)} · '
              '${l10n.traceFoldedCount(vm.traceCollapsed.length)}',
              key: const Key('trace-meta'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.labelSmall!.copyWith(
                color: context.colors.muted,
              ),
            ),
          ),
          const Spacer(flex: 1),
          if (vm.traceCollapsed.isNotEmpty)
            TextButton(
              key: const Key('trace-expand-all'),
              onPressed: vm.expandTraceFolds,
              child: Text(l10n.traceExpandAll),
            ),
          IconButton(
            key: const Key('trace-copy-markdown'),
            tooltip: l10n.traceCopyMarkdown,
            onPressed: () => _copy(context),
            icon: const Icon(Icons.content_copy_outlined, size: 18),
          ),
          const SizedBox(width: 8),
          SegmentedPicker<TraceDensity>(
            key: const Key('trace-density'),
            value: vm.traceDensity,
            options: [
              (TraceDensity.cards, l10n.traceDensityCards),
              (TraceDensity.read, l10n.traceDensityRead),
            ],
            onChanged: vm.setTraceDensity,
          ),
          IconButton(
            key: const Key('trace-close'),
            tooltip: '${l10n.traceClose} (Esc)',
            onPressed: vm.exitTrace,
            icon: const Icon(Icons.close, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    var message = l10n.traceCopied;
    try {
      await Clipboard.setData(ClipboardData(text: viewModel.traceMarkdown()));
    } catch (_) {
      message = l10n.traceCopyFailed;
    }
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// One end of the thread: the card it starts or stops at, and the control that
/// moves it. A pinned end holds; an unpinned one follows the arrows.
class _Endpoint extends StatelessWidget {
  const _Endpoint({
    required this.viewModel,
    required this.keyboard,
    required this.start,
    required this.label,
    required this.pinned,
  });

  final PlannerViewModel viewModel;
  final FocusNode keyboard;
  final bool start;
  final String label;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Tooltip(
            message: start ? l10n.traceStartAt : l10n.traceEndAt,
            child: TextButton(
              key: Key(start ? 'trace-start' : 'trace-end'),
              onPressed: () => _pick(context),
              style: TextButton.styleFrom(
                foregroundColor: pinned ? p.accent : p.text,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: context.type.titleMedium,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin, size: 12, color: p.accent),
                    ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // The ends are controls, not a headline; the dotted
                      // underline is what says "press to change".
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: p.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (pinned)
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              key: Key(start ? 'trace-unpin-start' : 'trace-unpin-end'),
              tooltip: start ? l10n.traceRunOnStart : l10n.traceRunOnEnd,
              padding: EdgeInsets.zero,
              iconSize: 13,
              visualDensity: VisualDensity.compact,
              onPressed: () => viewModel.unpinTrace(start: start),
              icon: Icon(Icons.close, color: p.muted),
            ),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final result = await showDialog<BoardSearchResult>(
      context: context,
      builder: (_) => BoardSearchDialog(viewModel: viewModel),
    );
    keyboard.requestFocus();
    if (result == null) return;
    start ? viewModel.traceStartAt(result.id) : viewModel.traceEndAt(result.id);
  }
}

/// The thread itself: fold bands above, one line of cards below.
class _TraceStrip extends StatelessWidget {
  const _TraceStrip({
    required this.viewModel,
    required this.trace,
    required this.items,
    required this.controller,
  });

  final PlannerViewModel viewModel;
  final Trace trace;
  final List<TraceItem> items;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final tiers = items.fold<int>(
      0,
      (deepest, item) => math.max(deepest, item.foldPath.length),
    );
    final width = items.length * _stride - _gap;
    return LayoutBuilder(
      builder: (context, box) => Scrollbar(
        controller: controller,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: _stagePadding,
            vertical: 20,
          ),
          // The thread never crops: too little height scrolls rather than
          // cutting the cards off.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0, box.maxHeight - 40),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var tier = 0; tier < tiers; tier++) ...[
                      _RibbonRow(
                        viewModel: viewModel,
                        items: items,
                        tier: tier,
                        width: width,
                        controller: controller,
                      ),
                      const SizedBox(height: _bandGap),
                    ],
                    SizedBox(
                      width: width,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (
                            var index = 0;
                            index < items.length;
                            index++
                          ) ...[
                            if (index > 0)
                              _Connector(
                                from: items[index - 1],
                                to: items[index],
                                foldTitle: viewModel.traceFoldTitle,
                              ),
                            _StepColumn(
                              viewModel: viewModel,
                              item: items[index],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trace.loopBackId != null) ...[
                      const SizedBox(height: 14),
                      _LoopNotice(viewModel: viewModel, trace: trace),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tier of the ribbon. A band names the fold its run of steps sits in, and
/// folding it back up is the same click.
class _RibbonRow extends StatelessWidget {
  const _RibbonRow({
    required this.viewModel,
    required this.items,
    required this.tier,
    required this.width,
    required this.controller,
  });

  final PlannerViewModel viewModel;
  final List<TraceItem> items;
  final int tier;
  final double width;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final bands = <Widget>[];
    var index = 0;
    while (index < items.length) {
      final fold = tier < items[index].foldPath.length
          ? items[index].foldPath[tier]
          : null;
      if (fold == null) {
        index++;
        continue;
      }
      var last = index;
      while (last + 1 < items.length &&
          tier < items[last + 1].foldPath.length &&
          items[last + 1].foldPath[tier] == fold) {
        last++;
      }
      final span = last - index + 1;
      bands.add(
        Positioned(
          left: index * _stride,
          width: span * _stride - _gap,
          top: 0,
          height: _bandHeight,
          child: _Band(
            id: fold,
            title: viewModel.traceFoldTitle(fold),
            controller: controller,
            left: index * _stride,
            width: span * _stride - _gap,
            onTap: () => viewModel.collapseTraceFold(fold),
          ),
        ),
      );
      index = last + 1;
    }
    return SizedBox(
      width: width,
      height: _bandHeight,
      child: Stack(clipBehavior: Clip.none, children: bands),
    );
  }
}

class _Band extends StatefulWidget {
  const _Band({
    required this.id,
    required this.title,
    required this.controller,
    required this.left,
    required this.width,
    required this.onTap,
  });

  final String id;
  final String title;
  final ScrollController controller;

  /// Where the band sits on the track. A fold whose run has scrolled past its
  /// own start is exactly the one that needs naming, so the name travels with
  /// the view instead of leaving with the band's left edge.
  final double left;
  final double width;
  final VoidCallback onTap;

  @override
  State<_Band> createState() => _BandState();
}

class _BandState extends State<_Band> {
  bool _hovered = false;

  /// How far the name has to travel right to stay on screen, never past the
  /// end of its own band.
  double _slide() {
    final controller = widget.controller;
    if (!controller.hasClients || !controller.position.hasContentDimensions) {
      return 0;
    }
    final hidden = controller.offset - _stagePadding - widget.left;
    return hidden.clamp(0.0, math.max(0.0, widget.width - 150));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final title = widget.title.isEmpty ? context.l10n.newFold : widget.title;
    return Semantics(
      button: true,
      label: context.l10n.traceCollapseFold(title),
      child: Tooltip(
        message: context.l10n.traceCollapseFold(title),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            key: Key('trace-band-${widget.id}'),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _hovered
                    ? p.accentDark
                    : Color.alphaBlend(
                        p.edge.withValues(alpha: .08),
                        p.surface,
                      ),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
                border: Border.all(color: _hovered ? p.accent : p.edgeMuted),
              ),
              child: AnimatedBuilder(
                animation: widget.controller,
                builder: (context, child) => Transform.translate(
                  offset: Offset(_slide(), 0),
                  child: child,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hovered ? p.accent : p.edge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.labelLarge!.copyWith(
                          color: _hovered ? p.accent : p.text,
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
    );
  }
}

/// A card and, under it, the continuations this step did not take.
class _StepColumn extends StatelessWidget {
  const _StepColumn({required this.viewModel, required this.item});

  final PlannerViewModel viewModel;
  final TraceItem item;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: _cardWidth,
        height: _cardHeight,
        child: _TraceCard(viewModel: viewModel, item: item),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: _cardWidth,
        height: _chipHeight,
        child: item.branchTargets.isEmpty
            ? null
            : Align(
                alignment: Alignment.centerLeft,
                child: _BranchChip(viewModel: viewModel, item: item),
              ),
      ),
    ],
  );
}

class _TraceCard extends StatelessWidget {
  const _TraceCard({required this.viewModel, required this.item});

  final PlannerViewModel viewModel;
  final TraceItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final l10n = context.l10n;
    final focused = item.covers(viewModel.traceFocus);
    final title = item.title.isEmpty
        ? (item.isFold ? l10n.newFold : l10n.newBlock)
        : item.title;
    return Tooltip(
      message: item.isCollapsedFold
          ? l10n.traceStepsInside(item.stepCount)
          : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: Key('trace-card-${item.id}'),
          // Tap focuses, and opens a folded card back up. Opening the step on
          // the board is the arrow on the card and Enter: a double-tap here
          // would hold every single tap for the double-tap window.
          onTap: () {
            viewModel.focusTraceStep(item.stepIndex);
            if (item.isCollapsedFold) viewModel.expandTraceFold(item.id);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: item.isCollapsedFold
                  ? Color.alphaBlend(p.edge.withValues(alpha: .07), p.surface)
                  : focused
                  ? p.surfaceHigh
                  : p.surface,
              borderRadius: BorderRadius.circular(
                item.isFold ? AppTheme.radiusProcessCard : AppTheme.radiusCard,
              ),
              border: Border.all(
                color: focused ? p.accent : p.line,
                width: focused ? 1.5 : 1,
              ),
            ),
            child: item.isCollapsedFold
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.traceStepsInside(item.stepCount),
                        style: context.type.labelMedium!.copyWith(
                          color: p.accent,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${item.stepIndex + 1}'.padLeft(2, '0'),
                            style: context.type.labelSmall!.copyWith(
                              color: item.isAnchor ? p.accent : p.muted,
                            ),
                          ),
                          if (item.isAnchor) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: l10n.traceAnchor,
                              child: Icon(
                                Icons.my_location,
                                size: 12,
                                color: p.accent,
                              ),
                            ),
                          ],
                          const Spacer(),
                          _OpenHere(viewModel: viewModel, item: item),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.type.bodySmall!.copyWith(
                            color: p.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _OpenHere extends StatelessWidget {
  const _OpenHere({required this.viewModel, required this.item});

  final PlannerViewModel viewModel;
  final TraceItem item;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 18,
    child: IconButton(
      key: Key('trace-open-${item.id}'),
      tooltip: '${context.l10n.traceOpenHere} (Enter)',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      iconSize: 15,
      onPressed: () => viewModel.openTraceStep(item.id),
      icon: Icon(Icons.north_east, color: context.colors.muted),
    ),
  );
}

class _BranchChip extends StatelessWidget {
  const _BranchChip({required this.viewModel, required this.item});

  final PlannerViewModel viewModel;
  final TraceItem item;

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final label = context.l10n.traceBranchCount(item.branchTargets.length);
    return Tooltip(
      message: label,
      child: TextButton.icon(
        key: Key('trace-branch-${item.id}'),
        onPressed: () =>
            viewModel.traceBranch(item.id, item.branchTargets.first),
        style: TextButton.styleFrom(
          foregroundColor: p.muted,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, _chipHeight),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: StadiumBorder(side: BorderSide(color: p.edgeMuted)),
          textStyle: context.type.labelSmall,
        ),
        icon: const Icon(Icons.alt_route, size: 14),
        label: Text(label),
      ),
    );
  }
}

/// The arrow between two steps. In a straightened thread a sibling arrow and
/// an arrow across two fold boundaries look the same, so the crossing is
/// marked here instead of being lost.
class _Connector extends StatelessWidget {
  const _Connector({
    required this.from,
    required this.to,
    required this.foldTitle,
  });

  final TraceItem from;
  final TraceItem to;
  final String Function(String id) foldTitle;

  TraceLink get _link {
    if (_same(from.foldPath, to.foldPath)) return TraceLink.same;
    if (_prefix(to.foldPath, from.foldPath)) return TraceLink.down;
    if (_prefix(from.foldPath, to.foldPath)) return TraceLink.up;
    return TraceLink.across;
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length && _prefix(a, b);

  static bool _prefix(List<String> path, List<String> prefix) {
    if (prefix.length > path.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final link = _link;
    final entered = to.foldPath.where((f) => !from.foldPath.contains(f));
    final left = from.foldPath.where((f) => !to.foldPath.contains(f));
    final message = switch (link) {
      TraceLink.same => '',
      TraceLink.down ||
      TraceLink.across => context.l10n.traceInto(foldTitle(entered.last)),
      TraceLink.up => context.l10n.traceOutOf(foldTitle(left.last)),
    };
    final icon = switch (link) {
      TraceLink.same => null,
      TraceLink.down => Icons.south_east,
      TraceLink.up => Icons.north_east,
      TraceLink.across => Icons.swap_horiz,
    };
    return SizedBox(
      width: _gap,
      height: _cardHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: _cardHeight / 2 - 6,
            height: 12,
            child: CustomPaint(painter: _ArrowPainter(p.edge)),
          ),
          if (icon != null)
            Positioned(
              left: -6,
              right: -6,
              top: _cardHeight / 2 - 34,
              child: Center(
                child: Tooltip(
                  message: message,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: p.accentDark,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Icon(icon, size: 13, color: p.accent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = AppTheme.arrowStroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width - AppTheme.arrowHeadLength, y),
      paint,
    );
    final head = Path()
      ..moveTo(size.width, y)
      ..lineTo(
        size.width - AppTheme.arrowHeadLength,
        y - AppTheme.arrowHeadHalfWidth,
      )
      ..lineTo(
        size.width - AppTheme.arrowHeadLength,
        y + AppTheme.arrowHeadHalfWidth,
      )
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) => oldDelegate.color != color;
}

class _LoopNotice extends StatelessWidget {
  const _LoopNotice({required this.viewModel, required this.trace});

  final PlannerViewModel viewModel;
  final Trace trace;

  @override
  Widget build(BuildContext context) {
    final target = trace.steps
        .where((step) => step.id == trace.loopBackId)
        .firstOrNull;
    if (target == null) return const SizedBox.shrink();
    final title = target.title.isEmpty ? context.l10n.newBlock : target.title;
    return TextButton.icon(
      key: const Key('trace-loop'),
      onPressed: () {
        final index = trace.steps.indexWhere((step) => step.id == target.id);
        if (index >= 0) viewModel.focusTraceStep(index);
      },
      style: TextButton.styleFrom(foregroundColor: context.colors.muted),
      icon: const Icon(Icons.replay, size: 15),
      label: Text(context.l10n.traceLoopsBack(title)),
    );
  }
}

/// The whole thread compressed into one strip: depth drawn as a profile, with
/// the part currently on screen framed and draggable.
class _TraceRail extends StatefulWidget {
  const _TraceRail({
    required this.viewModel,
    required this.items,
    required this.controller,
  });

  final PlannerViewModel viewModel;
  final List<TraceItem> items;
  final ScrollController controller;

  @override
  State<_TraceRail> createState() => _TraceRailState();
}

class _TraceRailState extends State<_TraceRail> {
  PlannerViewModel get viewModel => widget.viewModel;
  List<TraceItem> get items => widget.items;
  ScrollController get controller => widget.controller;

  /// The strip reports its extent only after it has been laid out, and a
  /// resting scroll position notifies no one, so the frame around the visible
  /// part is drawn on the frame after the thread lands.
  @override
  void initState() {
    super.initState();
    _afterLayout();
  }

  @override
  void didUpdateWidget(covariant _TraceRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != items.length) _afterLayout();
  }

  void _afterLayout() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) setState(() {});
  });

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final deepest = items.fold<int>(
      0,
      (value, item) => math.max(value, item.depth),
    );
    return Container(
      height: _railHeight,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final visible = _ready ? _window() : null;
                  return GestureDetector(
                    key: const Key('trace-rail'),
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                        _scrollTo(d.localPosition.dx, constraints.maxWidth),
                    onHorizontalDragUpdate: (d) =>
                        _scrollTo(d.localPosition.dx, constraints.maxWidth),
                    child: Semantics(
                      label: context.l10n.traceProfile,
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, _railHeight - 24),
                        painter: _ProfilePainter(
                          depths: [for (final item in items) item.depth],
                          deepest: deepest,
                          line: p.line,
                          accent: p.accent,
                          window: visible,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 16),
          // The top line is the board itself; every line below it is one fold
          // deeper, which the shape of the profile says better than a label.
          Align(
            alignment: Alignment.topRight,
            child: Text(
              context.l10n.rootLevel,
              style: context.type.labelSmall!.copyWith(color: p.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// The strip reports its extent only after it has been laid out, so the
  /// first frame of a trace draws the profile without a frame around it.
  bool get _ready =>
      controller.hasClients && controller.position.hasContentDimensions;

  /// Fraction of the thread on screen, as (left, width) in 0..1.
  (double, double)? _window() {
    final position = controller.position;
    final total = position.maxScrollExtent + position.viewportDimension;
    if (total <= 0 || position.maxScrollExtent <= 0) return null;
    return (position.pixels / total, position.viewportDimension / total);
  }

  void _scrollTo(double x, double railWidth) {
    if (!_ready || railWidth <= 0) return;
    final position = controller.position;
    if (position.maxScrollExtent <= 0) return;
    final total = position.maxScrollExtent + position.viewportDimension;
    final centre = (x / railWidth) * total - position.viewportDimension / 2;
    controller.jumpTo(centre.clamp(0.0, position.maxScrollExtent));
  }
}

class _ProfilePainter extends CustomPainter {
  const _ProfilePainter({
    required this.depths,
    required this.deepest,
    required this.line,
    required this.accent,
    required this.window,
  });

  final List<int> depths;
  final int deepest;
  final Color line;
  final Color accent;
  final (double, double)? window;

  @override
  void paint(Canvas canvas, Size size) {
    if (depths.isEmpty) return;
    final rows = deepest + 1;
    final step = rows > 1 ? (size.height - 8) / (rows - 1) : 0.0;
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var row = 0; row < rows; row++) {
      final y = 4 + row * step;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final points = [
      for (var index = 0; index < depths.length; index++)
        Offset(
          depths.length == 1
              ? size.width / 2
              : (index / (depths.length - 1)) * size.width,
          4 + depths[index] * step,
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = accent;
    for (final point in points) {
      canvas.drawCircle(point, 2, dot);
    }
    if (window case (final left, final width)?) {
      final rect = Rect.fromLTWH(
        left * size.width,
        0,
        math.max(width * size.width, 24),
        size.height,
      );
      canvas
        ..drawRect(rect, Paint()..color = accent.withValues(alpha: .12))
        ..drawRect(
          rect,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
    }
  }

  @override
  bool shouldRepaint(_ProfilePainter oldDelegate) =>
      oldDelegate.window != window ||
      oldDelegate.deepest != deepest ||
      oldDelegate.accent != accent ||
      !identical(oldDelegate.depths, depths);
}

/// The thread as a document: every description in full, every fold named, and
/// the words editable in place. Cards are for the shape; this is for reading.
class _TraceRead extends StatelessWidget {
  const _TraceRead({required this.viewModel, required this.trace});

  final PlannerViewModel viewModel;
  final Trace trace;

  @override
  Widget build(BuildContext context) {
    final canEdit = viewModel.canEdit && WriteAccessScope.canWriteOf(context);
    final rows = <Widget>[];
    var current = '';
    for (var index = 0; index < trace.steps.length; index++) {
      final step = trace.steps[index];
      final key = step.foldPath.join('/');
      if (key != current || index == 0) {
        current = key;
        rows.add(
          _ReadHeading(
            label: step.foldPath.isEmpty
                ? context.l10n.rootLevel
                : step.foldPath.map(viewModel.traceFoldTitle).join(' / '),
          ),
        );
      }
      rows.add(
        _ReadRow(
          key: ValueKey('trace-read-${step.id}'),
          viewModel: viewModel,
          step: step,
          number: index + 1,
          anchored: index == trace.anchorIndex,
          canEdit: canEdit,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadHeading extends StatelessWidget {
  const _ReadHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 6),
    child: Row(
      children: [
        Text(
          label,
          style: context.type.labelSmall!.copyWith(
            color: context.colors.muted,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: context.colors.line, height: 1)),
      ],
    ),
  );
}

class _ReadRow extends StatefulWidget {
  const _ReadRow({
    super.key,
    required this.viewModel,
    required this.step,
    required this.number,
    required this.anchored,
    required this.canEdit,
  });

  final PlannerViewModel viewModel;
  final TraceStep step;
  final int number;
  final bool anchored;
  final bool canEdit;

  @override
  State<_ReadRow> createState() => _ReadRowState();
}

class _ReadRowState extends State<_ReadRow> {
  late final _title = TextEditingController(text: widget.step.title);
  late final _description = TextEditingController(
    text: widget.step.description,
  );
  final _titleFocus = FocusNode(debugLabel: 'Trace step name');
  final _descriptionFocus = FocusNode(debugLabel: 'Trace step description');

  @override
  void didUpdateWidget(covariant _ReadRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(_title, _titleFocus, widget.step.title);
    _sync(_description, _descriptionFocus, widget.step.description);
  }

  /// An edit made elsewhere is picked up, but never while this field is the
  /// one being typed in.
  void _sync(TextEditingController controller, FocusNode focus, String value) {
    if (focus.hasFocus || controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    final vm = widget.viewModel;
    final step = widget.step;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 38,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${widget.number}'.padLeft(2, '0'),
                style: context.type.labelSmall!.copyWith(
                  color: widget.anchored ? p.accent : p.muted,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  key: ValueKey('trace-title-${step.id}'),
                  controller: _title,
                  focusNode: _titleFocus,
                  readOnly: !widget.canEdit,
                  maxLines: 1,
                  style: context.type.titleMedium,
                  // Hints invite typing; a reader who cannot type should not
                  // see literal "Name" and "Description" as content.
                  decoration: _bare(
                    context,
                    widget.canEdit ? context.l10n.name : '',
                  ),
                  onChanged: (value) =>
                      vm.updateTraceStep(step.id, title: value),
                ),
                TextField(
                  key: ValueKey('trace-description-${step.id}'),
                  controller: _description,
                  focusNode: _descriptionFocus,
                  readOnly: !widget.canEdit,
                  maxLines: null,
                  style: context.type.bodyMedium!.copyWith(color: p.muted),
                  decoration: _bare(
                    context,
                    widget.canEdit ? context.l10n.description : '',
                  ),
                  onChanged: (value) =>
                      vm.updateTraceStep(step.id, description: value),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            key: Key('trace-read-open-${step.id}'),
            tooltip: context.l10n.traceOpenHere,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            onPressed: () => vm.openTraceStep(step.id),
            icon: Icon(Icons.north_east, color: p.muted),
          ),
        ],
      ),
    );
  }

  InputDecoration _bare(BuildContext context, String label) => InputDecoration(
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    contentPadding: const EdgeInsets.symmetric(vertical: 4),
    hintText: label,
    // Italic keeps the invitation from reading as the card's own text.
    hintStyle: TextStyle(
      color: context.colors.muted.withValues(alpha: .55),
      fontStyle: FontStyle.italic,
    ),
  );
}
