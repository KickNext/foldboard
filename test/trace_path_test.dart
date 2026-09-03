import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/domain/use_cases/trace_path.dart';
import 'package:flutter_test/flutter_test.dart';

ArchitectureNode node(String id, {String? parent}) =>
    ArchitectureNode(id: id, title: id, parentId: parent);

ArchitectureGroup fold(String id, {String? parent}) =>
    ArchitectureGroup(id: id, title: id, parentId: parent);

ArchitectureEdge arrow(String from, String to) =>
    ArchitectureEdge(id: '$from-$to', from: from, to: to);

/// The board from the design: a chain that runs root → fold → fold → root.
class _Board {
  _Board({List<ArchitectureEdge> extra = const []})
    : edges = [
        arrow('kickoff', 'audit'),
        arrow('audit', 'mig'),
        arrow('freeze', 'copyc'),
        arrow('copyc', 'copys'),
        arrow('copys', 'rec'),
        arrow('diff', 'fix'),
        arrow('rec', 'dry'),
        arrow('dry', 'cutover'),
        arrow('cutover', 'aft'),
        arrow('dun', 'close'),
        arrow('aft', 'done'),
        ...extra,
      ];

  final nodes = [
    node('kickoff'),
    node('audit'),
    node('cutover'),
    node('done'),
    node('freeze', parent: 'mig'),
    node('copyc', parent: 'mig'),
    node('copys', parent: 'mig'),
    node('dry', parent: 'mig'),
    node('diff', parent: 'rec'),
    node('fix', parent: 'rec'),
    node('dun', parent: 'aft'),
    node('close', parent: 'aft'),
  ];
  final groups = [fold('mig'), fold('rec', parent: 'mig'), fold('aft')];
  final List<ArchitectureEdge> edges;

  Trace? trace({
    String? anchorId,
    String? fromId,
    String? toId,
    String? cameFromId,
  }) => const TracePath()(
    nodes: nodes,
    groups: groups,
    edges: edges,
    anchorId: anchorId,
    fromId: fromId,
    toId: toId,
    cameFromId: cameFromId,
  );
}

void main() {
  test('straightens one chain across three levels', () {
    final trace = _Board().trace(anchorId: 'copyc')!;
    expect(trace.steps.map((s) => s.id), [
      'kickoff',
      'audit',
      'freeze',
      'copyc',
      'copys',
      'diff',
      'fix',
      'dry',
      'cutover',
      'dun',
      'close',
      'done',
    ]);
    expect(trace.anchor!.id, 'copyc');
    expect(trace.loopBackId, isNull);
  });

  test('a fold with contents is a path, never a step', () {
    final trace = _Board().trace(anchorId: 'kickoff')!;
    expect(trace.steps.map((s) => s.id), isNot(contains('mig')));
    expect(trace.steps.map((s) => s.id), isNot(contains('rec')));
    final byId = {for (final step in trace.steps) step.id: step};
    expect(byId['kickoff']!.foldPath, isEmpty);
    expect(byId['freeze']!.foldPath, ['mig']);
    expect(byId['diff']!.foldPath, ['mig', 'rec']);
    expect(byId['dun']!.foldPath, ['aft']);
  });

  test('an empty fold stays a step of its own', () {
    final board = _Board(extra: [arrow('done', 'empty')]);
    board.groups.add(fold('empty'));
    final trace = board.trace(anchorId: 'done')!;
    expect(trace.steps.last.id, 'empty');
    expect(trace.steps.last.isFold, isTrue);
  });

  test('crossings keep their direction', () {
    final trace = _Board().trace(anchorId: 'kickoff')!;
    final byId = {for (final step in trace.steps) step.id: step};
    TraceLink linkTo(String from, String to) =>
        Trace.link(byId[from]!, byId[to]!);
    expect(linkTo('kickoff', 'audit'), TraceLink.same);
    expect(linkTo('audit', 'freeze'), TraceLink.down);
    expect(linkTo('copys', 'diff'), TraceLink.down);
    expect(linkTo('fix', 'dry'), TraceLink.up);
    expect(linkTo('dry', 'cutover'), TraceLink.up);
    expect(linkTo('close', 'done'), TraceLink.up);
  });

  test('a step that leaves one fold for another crosses sideways', () {
    final board = _Board(extra: [arrow('dry', 'dun')]);
    final trace = board.trace(anchorId: 'dry')!;
    final byId = {for (final step in trace.steps) step.id: step};
    expect(byId.containsKey('dun'), isTrue);
    expect(Trace.link(byId['dry']!, byId['dun']!), TraceLink.across);
  });

  test('the thread takes one branch and reports the rest', () {
    final board = _Board(extra: [arrow('audit', 'legacy')]);
    board.nodes.add(node('legacy', parent: 'mig'));
    final trace = board.trace(anchorId: 'kickoff')!;
    final audit = trace.steps.firstWhere((step) => step.id == 'audit');
    // The longer continuation is the thread; the dead end is a branch.
    expect(trace.steps.map((s) => s.id), contains('freeze'));
    expect(trace.steps.map((s) => s.id), isNot(contains('legacy')));
    expect(audit.branchTargets, ['legacy']);
  });

  test('tracing a branch target follows that line instead', () {
    final board = _Board(extra: [arrow('audit', 'legacy')]);
    board.nodes.add(node('legacy', parent: 'mig'));
    final trace = board.trace(anchorId: 'legacy', cameFromId: 'audit')!;
    expect(trace.steps.map((s) => s.id), ['kickoff', 'audit', 'legacy']);
    expect(trace.anchor!.id, 'legacy');
  });

  test('a loop is reported once, not unrolled twice', () {
    final board = _Board(extra: [arrow('done', 'kickoff')]);
    final trace = board.trace(anchorId: 'kickoff')!;
    final ids = trace.steps.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(trace.loopBackId, isNotNull);
  });

  test('between returns only the segment', () {
    final trace = _Board().trace(fromId: 'copyc', toId: 'cutover')!;
    expect(trace.steps.map((s) => s.id), [
      'copyc',
      'copys',
      'diff',
      'fix',
      'dry',
      'cutover',
    ]);
  });

  test('between returns nothing when the cards are not connected', () {
    final board = _Board();
    board.nodes.add(node('stray'));
    expect(board.trace(fromId: 'stray', toId: 'done'), isNull);
    expect(board.trace(fromId: 'done', toId: 'kickoff'), isNull);
  });

  test('with no anchor the longest chain is traced', () {
    final board = _Board(extra: [arrow('side', 'sideTwo')]);
    board.nodes.addAll([node('side'), node('sideTwo')]);
    final trace = board.trace()!;
    expect(trace.steps.first.id, 'kickoff');
    expect(trace.steps.last.id, 'done');
  });

  test('a pinned start runs forward only, a pinned end backward only', () {
    final board = _Board();
    expect(board.trace(fromId: 'copys')!.steps.map((s) => s.id), [
      'copys',
      'diff',
      'fix',
      'dry',
      'cutover',
      'dun',
      'close',
      'done',
    ]);
    expect(board.trace(toId: 'copys')!.steps.map((s) => s.id), [
      'kickoff',
      'audit',
      'freeze',
      'copyc',
      'copys',
    ]);
  });

  test('a pinned end may sit anywhere, not only on the open level', () {
    // The whole point: the two ends live in different folds.
    final trace = _Board().trace(fromId: 'freeze', toId: 'close')!;
    expect(trace.steps.first.foldPath, ['mig']);
    expect(trace.steps.last.foldPath, ['aft']);
    expect(trace.steps.map((s) => s.id), contains('diff'));
  });

  test('one card at both ends traces the loop through it', () {
    final board = _Board(extra: [arrow('done', 'kickoff')]);
    final trace = board.trace(fromId: 'audit', toId: 'audit')!;
    final ids = trace.steps.map((s) => s.id).toList();
    expect(ids.first, 'audit');
    expect(ids, contains('done'));
    expect(ids.toSet().length, ids.length);
    expect(trace.loopBackId, 'audit');
  });

  test('a card with no way back to itself has no loop to trace', () {
    expect(_Board().trace(fromId: 'audit', toId: 'audit'), isNull);
  });

  test('pinning into a fold lands on the step the thread reaches', () {
    final trace = _Board().trace(fromId: 'kickoff', toId: 'rec')!;
    expect(trace.steps.last.id, 'diff');
  });

  test('an empty board has nothing to trace', () {
    expect(
      const TracePath()(nodes: const [], groups: const [], edges: const []),
      isNull,
    );
  });

  test('the thread reads as a plain document, fold path and all', () {
    final board = _Board();
    board.nodes[0] = const ArchitectureNode(
      id: 'kickoff',
      title: 'Kickoff',
      description: 'Freeze the scope.',
    );
    final trace = board.trace(anchorId: 'diff')!;
    final markdown = traceToMarkdown(trace, (id) => id.toUpperCase());
    expect(markdown, startsWith('# Trace: Kickoff → done'));
    expect(markdown, contains('1. **Kickoff**  `/`'));
    expect(markdown, contains('   Freeze the scope.'));
    expect(markdown, contains('6. **diff**  `/MIG/REC`'));
    expect(markdown, endsWith('\n'));
  });

  test('markdown escapes card names and reports a loop', () {
    final board = _Board(extra: [arrow('done', 'kickoff')]);
    board.nodes[1] = const ArchitectureNode(
      id: 'audit',
      title: 'Plans *and* _trials_',
    );
    final markdown = traceToMarkdown(
      board.trace(anchorId: 'kickoff')!,
      (id) => id,
    );
    expect(markdown, contains(r'**Plans \*and\* \_trials\_**'));
    expect(markdown, contains('_Loops back to'));
  });

  test('a single card with no arrows is its own thread', () {
    final trace = const TracePath()(
      nodes: [node('only')],
      groups: const [],
      edges: const [],
      anchorId: 'only',
    )!;
    expect(trace.steps.single.id, 'only');
    expect(trace.steps.single.branchTargets, isEmpty);
  });
}
