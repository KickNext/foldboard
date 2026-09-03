import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

PlannerViewModel board() {
  final repository = ArchitectureRepository();
  repository.applyChanges({
    'groups': [
      {'id': 'proc', 'title': 'Process', 'x': 100.0, 'y': 100.0},
    ],
    'nodes': [
      {'id': 'root', 'title': 'Root card', 'x': 600.0, 'y': 400.0},
      {'id': 'inner-a', 'title': 'Inner A', 'parentId': 'proc'},
      {'id': 'inner-b', 'title': 'Inner B', 'parentId': 'proc'},
    ],
    'edges': [
      {'id': 'inside', 'from': 'inner-a', 'to': 'inner-b'},
      {'id': 'crossing', 'from': 'root', 'to': 'proc'},
    ],
  });
  return PlannerViewModel(repository: repository, registerBridge: false);
}

void main() {
  late PlannerViewModel vm;
  setUp(() => vm = board());
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  test('duplicating a block copies it beside the original', () {
    vm.select('root');
    expect(vm.duplicateSelection(), isTrue);

    expect(vm.nodes.length, 4);
    final copy = vm.nodes.firstWhere(
      (n) => n.id != 'root' && n.parentId == null,
    );
    expect(copy.title, 'Root card');
    expect(copy.position, isNot(const Offset(600, 400)));
    expect(vm.selectedId, copy.id);
    // The original keeps its arrows; the copy starts unconnected.
    expect(
      vm.edges.where((e) => e.from == copy.id || e.to == copy.id),
      isEmpty,
    );
  });

  test('duplicating a process deep-copies its level and inner arrows', () {
    vm.selectGroup('proc');
    expect(vm.duplicateSelection(), isTrue);

    final copy = vm.groups.firstWhere((g) => g.id != 'proc');
    final children = vm.nodes.where((n) => n.parentId == copy.id).toList();
    expect(children.map((n) => n.title), ['Inner A', 'Inner B']);
    expect(
      vm.edges.any(
        (e) =>
            e.from == children.first.id &&
            e.to == children.last.id &&
            e.id != 'inside',
      ),
      isTrue,
      reason: 'the arrow inside the process is copied with new ids',
    );
    // The arrow from the root card to the original process is not duplicated.
    expect(vm.edges.where((e) => e.to == copy.id), isEmpty);
    expect(vm.nodes.firstWhere((n) => n.id == 'inner-a').parentId, 'proc');
  });

  test('copy then paste places the card on the level in view', () {
    vm.select('root');
    expect(vm.copySelection(), isTrue);
    expect(vm.notice, contains('Root card'));
    expect(vm.canPaste, isTrue);

    vm.openLevel('proc');
    expect(vm.paste(), isTrue);
    final pasted = vm.nodes.firstWhere((n) => n.id == vm.selectedId);
    expect(pasted.parentId, 'proc');
    expect(pasted.title, 'Root card');
    // Pasting twice yields two independent cards.
    expect(vm.paste(), isTrue);
    expect(vm.nodes.where((n) => n.parentId == 'proc').length, 4);
  });

  test('paste without a clipboard says so and changes nothing', () {
    final before = vm.prettyJson;
    expect(vm.paste(), isFalse);
    expect(vm.notice, isNotNull);
    expect(vm.prettyJson, before);
  });

  test('a copy is a snapshot: later edits to the source do not follow it', () {
    vm.select('root');
    vm.copySelection();
    vm.updateSelected(title: 'Renamed');
    expect(vm.paste(), isTrue);
    expect(
      vm.nodes.firstWhere((n) => n.id == vm.selectedId).title,
      'Root card',
    );
  });

  test('duplicate is one undo step', () {
    vm.selectGroup('proc');
    List<String> ids() => [
      ...vm.groups.map((g) => g.id),
      ...vm.nodes.map((n) => n.id),
      ...vm.edges.map((e) => e.id),
    ];
    final before = ids();
    expect(vm.duplicateSelection(), isTrue);
    expect(ids().length, greaterThan(before.length));
    vm.undo();
    expect(ids(), before);
  });

  test('external cards cannot be copied', () {
    vm.openLevel('proc');
    final reference = vm.canvasNodes
        .map((n) => n.id)
        .firstWhere(vm.levelGraph.referenceIds.contains);
    // selectCard is the board's entry point; it keeps a proxy selected
    // instead of navigating to the original's level.
    vm.selectCard(reference);
    expect(vm.selectedIsReference, isTrue);
    expect(vm.canCopySelection, isFalse);
    expect(vm.copySelection(), isFalse);
    expect(vm.duplicateSelection(), isFalse);
  });

  test('a read-only board refuses duplicate and paste', () {
    vm.select('root');
    vm.copySelection();
    final locked = PlannerViewModel(
      repository: ArchitectureRepository(readOnly: true),
      registerBridge: false,
    );
    addTearDown(() {
      locked.dispose();
      locked.repository.dispose();
    });
    expect(locked.canEdit, isFalse);
    expect(locked.duplicateSelection(), isFalse);
    expect(locked.paste(), isFalse);
    expect(locked.nodes, isEmpty);
  });
}
