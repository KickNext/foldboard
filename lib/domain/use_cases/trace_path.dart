import '../models/architecture_models.dart';

/// How one step sits against the previous one. In a straightened thread an
/// arrow between siblings and an arrow across two fold boundaries look the
/// same, so the crossing is carried here instead of being lost.
enum TraceLink { same, down, up, across }

/// One step of a straightened thread.
///
/// A step is always a card, or a fold with nothing inside it. A fold that has
/// contents is never a step: the thread descends into it and the fold is
/// carried in [foldPath] instead, so the line stays flat while the nesting it
/// crosses stays readable.
class TraceStep {
  const TraceStep({
    required this.id,
    required this.title,
    required this.description,
    required this.foldPath,
    required this.isFold,
    this.branchTargets = const [],
  });

  final String id;
  final String title;
  final String description;

  /// Fold IDs from the outermost inwards. Empty on the root level.
  final List<String> foldPath;

  /// True for an empty fold standing in as a step of its own.
  final bool isFold;

  /// Continuations of this step the thread did not take. A thread is always
  /// one line; these are the other lines it could have been.
  final List<String> branchTargets;

  int get depth => foldPath.length;
}

/// One straightened thread through the board, from its source to its sink.
class Trace {
  const Trace({
    required this.steps,
    required this.anchorIndex,
    this.loopBackId,
  });

  final List<TraceStep> steps;

  /// The step the thread was traced from. The rest of the line is context.
  final int anchorIndex;

  /// Set when the walk stopped because the thread returns to a step it has
  /// already passed. A loop is reported, never unrolled twice.
  final String? loopBackId;

  TraceStep? get anchor => anchorIndex >= 0 && anchorIndex < steps.length
      ? steps[anchorIndex]
      : null;

  static TraceLink link(TraceStep from, TraceStep to) {
    if (_samePath(from.foldPath, to.foldPath)) return TraceLink.same;
    if (_startsWith(to.foldPath, from.foldPath)) return TraceLink.down;
    if (_startsWith(from.foldPath, to.foldPath)) return TraceLink.up;
    return TraceLink.across;
  }

  static bool _samePath(List<String> a, List<String> b) =>
      a.length == b.length && _startsWith(a, b);

  static bool _startsWith(List<String> path, List<String> prefix) {
    if (prefix.length > path.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) return false;
    }
    return true;
  }
}

/// Straightens one thread out of the board.
///
/// The board is a graph across levels; a trace is one line through it. Where a
/// step continues in several directions the walk takes a single one — the
/// longest continuation, then the smallest change of depth, then the order the
/// arrows were made — and reports the rest as branches.
class TracePath {
  const TracePath();

  /// Returns the thread to show, or null when there is none.
  ///
  /// [fromId] and [toId] pin an end of the thread: both pinned trace the
  /// segment between them, one pinned lets the thread run to its own source or
  /// sink, and the same card pinned at both ends traces the loop through it.
  /// With nothing pinned the thread through [anchorId] is traced, and with no
  /// anchor either, the longest chain on the board.
  Trace? call({
    required List<ArchitectureNode> nodes,
    required List<ArchitectureGroup> groups,
    required List<ArchitectureEdge> edges,
    String? anchorId,
    String? fromId,
    String? toId,
    String? cameFromId,
  }) {
    final board = _Board(nodes, groups, edges);
    if (fromId != null && toId != null) return board.between(fromId, toId);
    if (fromId != null) {
      final start = board.resolve(fromId, forward: true);
      return start == null ? null : board.thread(start, behind: false);
    }
    if (toId != null) {
      final end = board.resolve(toId, forward: true);
      return end == null ? null : board.thread(end, ahead: false);
    }
    final start = anchorId == null
        ? board.longestStart()
        : board.resolve(anchorId, forward: true);
    if (start == null) return null;
    return board.thread(start, cameFromId: cameFromId);
  }
}

/// The thread as a plain document: what the Read density shows, and what gets
/// handed to a person or an agent. Coordinates and IDs are left out on
/// purpose — the order and the fold each step sits in are the whole content.
String traceToMarkdown(Trace trace, String Function(String id) foldTitle) {
  if (trace.steps.isEmpty) return '';
  final buffer = StringBuffer()
    ..writeln(
      '# Trace: ${_inline(trace.steps.first.title)} → '
      '${_inline(trace.steps.last.title)}',
    );
  for (var index = 0; index < trace.steps.length; index++) {
    final step = trace.steps[index];
    final path = step.foldPath.isEmpty
        ? '/'
        : '/${step.foldPath.map(foldTitle).map(_code).join('/')}';
    buffer
      ..writeln()
      ..writeln('${index + 1}. **${_inline(step.title)}**  `$path`');
    if (step.description.trim().isNotEmpty) {
      buffer.writeln('   ${_flat(step.description)}');
    }
  }
  if (trace.loopBackId != null) {
    final target = trace.steps
        .where((step) => step.id == trace.loopBackId)
        .firstOrNull;
    buffer
      ..writeln()
      ..writeln('_Loops back to ${_inline(target?.title ?? '')}._');
  }
  return '${buffer.toString().trimRight()}\n';
}

String _inline(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('*', '\\*')
    .replaceAll('_', '\\_')
    .replaceAll('[', '\\[')
    .replaceAll(']', '\\]')
    .replaceAll(RegExp(r'[\r\n]+'), ' ')
    .trim();

String _code(String value) => value.replaceAll('`', 'ˋ');

String _flat(String value) =>
    value.trim().replaceAll(RegExp(r'[\r\n]+'), '<br>');

class _Item {
  const _Item(this.title, this.description, this.parentId, this.isFold);
  final String title;
  final String description;
  final String? parentId;
  final bool isFold;
}

class _Candidate {
  const _Candidate(this.id, this.edge);
  final String id;

  /// Index in the board's arrow list, which is the order they were made in.
  final int edge;
}

class _Board {
  _Board(
    List<ArchitectureNode> nodes,
    List<ArchitectureGroup> groups,
    this.edges,
  ) {
    for (final node in nodes) {
      _items[node.id] = _Item(
        node.title,
        node.description,
        node.parentId,
        false,
      );
      _order.add(node.id);
    }
    for (final group in groups) {
      _items[group.id] = _Item(
        group.title,
        group.description,
        group.parentId,
        true,
      );
      _order.add(group.id);
    }
    for (final id in _order) {
      (_children[_items[id]!.parentId] ??= []).add(id);
    }
    for (var index = 0; index < edges.length; index++) {
      final edge = edges[index];
      if (!_items.containsKey(edge.from) || !_items.containsKey(edge.to)) {
        continue;
      }
      (_out[edge.from] ??= []).add(index);
      (_in[edge.to] ??= []).add(index);
    }
  }

  final List<ArchitectureEdge> edges;
  final _items = <String, _Item>{};
  final _order = <String>[];
  final _children = <String?, List<String>>{};
  final _out = <String, List<int>>{};
  final _in = <String, List<int>>{};
  final _chainForward = <String, int>{};
  final _chainBackward = <String, int>{};
  final _stack = <String>{};
  bool _cut = false;

  List<String> foldPathOf(String id) {
    final path = <String>[];
    final seen = <String>{};
    var parent = _items[id]?.parentId;
    while (parent != null && _items.containsKey(parent) && seen.add(parent)) {
      path.insert(0, parent);
      parent = _items[parent]!.parentId;
    }
    return path;
  }

  bool _within(String id, String fold) {
    final seen = <String>{};
    var parent = _items[id]?.parentId;
    while (parent != null && seen.add(parent)) {
      if (parent == fold) return true;
      parent = _items[parent]!.parentId;
    }
    return false;
  }

  /// Walks a fold down to the step the thread actually reaches: its entry when
  /// moving forward, its exit when moving backward. An empty fold resolves to
  /// itself, because there is nothing inside to stand in for it.
  String? resolve(String id, {required bool forward}) {
    var current = id;
    final seen = <String>{};
    while (seen.add(current)) {
      final item = _items[current];
      if (item == null) return null;
      if (!item.isFold) return current;
      final children = _children[current] ?? const <String>[];
      if (children.isEmpty) return current;
      final next = _edgeOf(current, children, forward: forward);
      if (next == null || next == current) return current;
      current = next;
    }
    return current;
  }

  String? _edgeOf(String fold, List<String> children, {required bool forward}) {
    for (final id in children) {
      final links = (forward ? _in[id] : _out[id]) ?? const <int>[];
      final connected = links.any((index) {
        final other = forward ? edges[index].from : edges[index].to;
        return other == fold || _within(other, fold);
      });
      if (!connected) return id;
    }
    // Every child has an inner predecessor: the level is a loop, so any entry
    // is as good as another. Board order keeps the choice stable.
    return children.first;
  }

  List<_Candidate> candidates(String id, {required bool forward}) {
    var current = id;
    final climbed = <String>{};
    while (true) {
      final links = (forward ? _out[current] : _in[current]) ?? const <int>[];
      final found = <String, _Candidate>{};
      for (final index in links) {
        final other = forward ? edges[index].to : edges[index].from;
        // Climbing out of a fold, an arrow pointing back into it is not a
        // continuation. Boards saved before the ancestor rule can hold one.
        if (current != id && (other == id || _within(other, current))) continue;
        final resolved = resolve(other, forward: forward);
        if (resolved == null || resolved == id) continue;
        found.putIfAbsent(resolved, () => _Candidate(resolved, index));
      }
      if (found.isNotEmpty) return found.values.toList();
      final parent = _items[current]?.parentId;
      if (parent == null || !climbed.add(parent)) return const [];
      current = parent;
    }
  }

  /// Length of the longest line onwards from [id]. Used only to rank branches,
  /// so a value cut short by a loop is never cached.
  int _chainLength(String id, bool forward) {
    final memo = forward ? _chainForward : _chainBackward;
    final cached = memo[id];
    if (cached != null) return cached;
    if (!_stack.add(id)) {
      _cut = true;
      return 0;
    }
    final cutOutside = _cut;
    _cut = false;
    var best = 0;
    for (final candidate in candidates(id, forward: forward)) {
      final length = _chainLength(candidate.id, forward) + 1;
      if (length > best) best = length;
    }
    _stack.remove(id);
    if (!_cut) memo[id] = best;
    _cut = _cut || cutOutside;
    return best;
  }

  _Candidate _pick(String from, List<_Candidate> options, bool forward) {
    final depth = foldPathOf(from).length;
    var best = options.first;
    var bestChain = -1;
    var bestJump = 1 << 30;
    for (final option in options) {
      final chain = _chainLength(option.id, forward);
      final jump = (foldPathOf(option.id).length - depth).abs();
      final better =
          chain > bestChain ||
          (chain == bestChain &&
              (jump < bestJump ||
                  (jump == bestJump && option.edge < best.edge)));
      if (better) {
        best = option;
        bestChain = chain;
        bestJump = jump;
      }
    }
    return best;
  }

  Trace thread(
    String start, {
    String? cameFromId,
    bool ahead = true,
    bool behind = true,
  }) {
    final visited = {start};
    final onwards = <String>[];
    var current = start;
    String? loopBack;
    while (ahead) {
      final options = candidates(current, forward: true);
      if (options.isEmpty) break;
      final chosen = _pick(current, options, true);
      if (!visited.add(chosen.id)) {
        loopBack = chosen.id;
        break;
      }
      onwards.add(chosen.id);
      current = chosen.id;
    }
    final backwards = <String>[];
    current = start;
    var first = true;
    while (behind) {
      final options = candidates(current, forward: false);
      if (options.isEmpty) break;
      var chosen = _pick(current, options, false);
      if (first && cameFromId != null) {
        chosen = options.firstWhere(
          (option) => option.id == cameFromId,
          orElse: () => chosen,
        );
      }
      first = false;
      if (!visited.add(chosen.id)) {
        loopBack ??= chosen.id;
        break;
      }
      backwards.insert(0, chosen.id);
      current = chosen.id;
    }
    return _build(
      [...backwards, start, ...onwards],
      anchorIndex: backwards.length,
      loopBackId: loopBack,
    );
  }

  /// The shortest thread from one card to another. The same card at both ends
  /// asks for the loop through it, which is reported once, like any other loop.
  Trace? between(String fromId, String toId) {
    final start = resolve(fromId, forward: true);
    final goal = resolve(toId, forward: true);
    if (start == null || goal == null) return null;
    final loop = start == goal;
    final cameFrom = <String, String>{};
    final queue = <String>[start];
    final seen = {start};
    var head = 0;
    while (head < queue.length) {
      final current = queue[head++];
      for (final option in candidates(current, forward: true)) {
        if (option.id == goal) {
          final ids = <String>[current];
          var walk = current;
          for (
            var previous = cameFrom[walk];
            previous != null;
            previous = cameFrom[walk]
          ) {
            ids.insert(0, previous);
            walk = previous;
          }
          return _build(
            loop ? ids : [...ids, goal],
            anchorIndex: 0,
            loopBackId: loop ? start : null,
          );
        }
        if (!seen.add(option.id)) continue;
        cameFrom[option.id] = current;
        queue.add(option.id);
      }
    }
    return null;
  }

  /// The longest chain on the board, for a trace asked for with nothing
  /// selected. Sources are preferred; a board that is all loops has none.
  String? longestStart() {
    String? best;
    var bestLength = 0;
    String? fallback;
    var fallbackLength = 0;
    for (final id in _order) {
      if (resolve(id, forward: true) != id) continue;
      final length = _chainLength(id, true);
      if (length > fallbackLength) {
        fallbackLength = length;
        fallback = id;
      }
      if (candidates(id, forward: false).isNotEmpty) continue;
      if (length > bestLength) {
        bestLength = length;
        best = id;
      }
    }
    return best ?? fallback;
  }

  Trace _build(
    List<String> ids, {
    required int anchorIndex,
    String? loopBackId,
  }) {
    final steps = <TraceStep>[];
    for (var index = 0; index < ids.length; index++) {
      final id = ids[index];
      final item = _items[id]!;
      final next = index + 1 < ids.length ? ids[index + 1] : null;
      final branches = [
        for (final option in candidates(id, forward: true))
          if (option.id != next) option.id,
      ];
      steps.add(
        TraceStep(
          id: id,
          title: item.title,
          description: item.description,
          foldPath: List.unmodifiable(foldPathOf(id)),
          isFold: item.isFold,
          branchTargets: List.unmodifiable(branches),
        ),
      );
    }
    return Trace(
      steps: List.unmodifiable(steps),
      anchorIndex: anchorIndex,
      loopBackId: loopBackId,
    );
  }
}
