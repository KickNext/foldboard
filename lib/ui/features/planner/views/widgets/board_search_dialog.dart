import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../l10n/l10n.dart';
import '../../../../core/app_theme.dart';
import '../../../../core/fold_icon.dart';
import '../../view_models/board_search_result.dart';
import '../../view_models/planner_view_model.dart';

class BoardSearchDialog extends StatefulWidget {
  const BoardSearchDialog({super.key, required this.viewModel});
  final PlannerViewModel viewModel;
  @override
  State<BoardSearchDialog> createState() => _BoardSearchDialogState();
}

class _BoardSearchDialogState extends State<BoardSearchDialog> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<BoardSearchResult> _results = [];
  int _selected = 0;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    widget.viewModel.repository.addListener(_refresh);
  }

  void _refresh() {
    final query = _query.text.trim();
    setState(() {
      _results = query.isEmpty ? const [] : widget.viewModel.searchBoard(query);
      _selected = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    widget.viewModel.repository.removeListener(_refresh);
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _choose(int index) {
    if (index >= 0 && index < _results.length) {
      _finish(_results[index]);
    }
  }

  void _finish([BoardSearchResult? result]) {
    if (_closing) return;
    _closing = true;
    Navigator.pop(context, result);
  }

  KeyEventResult _key(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _finish();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        _focus.hasFocus &&
        !_query.value.composing.isValid) {
      _choose(_selected);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_results.isNotEmpty) {
        final direction = event.logicalKey == LogicalKeyboardKey.arrowDown
            ? 1
            : -1;
        setState(
          () =>
              _selected = (_selected + direction).clamp(0, _results.length - 1),
        );
        if (_scroll.hasClients) {
          final top = _selected * 88.0;
          final bottom = top + 88;
          final viewport = _scroll.position.viewportDimension;
          final offset = top < _scroll.offset
              ? top
              : bottom > _scroll.offset + viewport
              ? bottom - viewport
              : _scroll.offset;
          _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent));
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('board-search-dialog'),
    alignment: Alignment.topCenter,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 64),
    clipBehavior: Clip.antiAlias,
    child: Focus(
      onKeyEvent: _key,
      child: SizedBox(
        width: 640,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.findOnBoard,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: _finish,
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('board-search'),
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.l10n.searchBoardHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.l10n.clearSearch,
                          onPressed: () {
                            _query.clear();
                            _refresh();
                            _focus.requestFocus();
                          },
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
                onChanged: (_) => _refresh(),
                onSubmitted: (_) => _choose(_selected),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _query.text.trim().isEmpty
                      ? context.l10n.searchAllLevels
                      : context.l10n.searchResultCount(_results.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _query.text.trim().isEmpty
                              ? widget.viewModel.searchBoard('').isEmpty
                                    ? context.l10n.emptySearchBoard
                                    : context.l10n.searchStartHint
                              : context.l10n.noSearchResults,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      itemExtent: 88,
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        // The same glyphs the inspector uses; the folder
                        // stays with projects.
                        final (
                          Widget icon,
                          String label,
                        ) = switch (result.kind) {
                          BoardSearchKind.block => (
                            const Icon(Icons.view_agenda_outlined, size: 20),
                            context.l10n.block,
                          ),
                          BoardSearchKind.process => (
                            const FoldIcon(size: 20),
                            context.l10n.fold,
                          ),
                        };
                        final query = _query.text.trim().toLowerCase();
                        final lines = result.description
                            .split('\n')
                            .where((s) => s.trim().isNotEmpty);
                        final excerpt =
                            lines
                                .where(
                                  (s) =>
                                      query.isNotEmpty &&
                                      s.toLowerCase().contains(query),
                                )
                                .firstOrNull ??
                            lines.firstOrNull ??
                            '';
                        return Material(
                          color: index == _selected
                              ? Theme.of(context).colorScheme.primary
                                    .withValues(alpha: .10)
                              : Colors.transparent,
                          child: InkWell(
                            key: ValueKey('search-result-${result.id}'),
                            onTap: () => _choose(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  icon,
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          result.title.isEmpty
                                              ? (result.kind ==
                                                        BoardSearchKind.process
                                                    ? context.l10n.newFold
                                                    : context.l10n.newBlock)
                                              : result.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.type.titleMedium,
                                        ),
                                        Text(
                                          '$label · ${result.path}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        if (excerpt.isNotEmpty)
                                          Text(
                                            excerpt,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward, size: 16),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
