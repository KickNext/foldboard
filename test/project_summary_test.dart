import 'dart:convert';

import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/storage_keys.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/project_stores.dart';

void main() {
  late ProjectStores stores;
  late ProjectsViewModel vm;
  setUp(() {
    stores = ProjectStores();
    stores
        .board(StorageKeys.projectBoard(Project.defaultId))
        .value = jsonEncode({
      'nodes': [
        {'id': 'a', 'title': 'A'},
        {'id': 'b', 'title': 'B'},
      ],
      'groups': [
        {'id': 'g', 'title': 'G'},
      ],
      'edges': [
        {'id': 'e', 'from': 'a', 'to': 'b'},
      ],
    });
    vm = ProjectsViewModel(repository: stores.repository());
  });
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  test('the projects list counts a board without opening it', () {
    expect(vm.summary(Project.defaultId), (blocks: 2, processes: 1, arrows: 1));
    expect(vm.planner, isNull);
  });

  test('an empty project reports zeroes and a corrupt one reports null', () {
    expect(vm.create('Fresh'), isTrue);
    expect(vm.showProjects(), isTrue);
    final fresh = vm.projects.last;
    expect(vm.summary(fresh.id)?.blocks, 0);

    stores.board(StorageKeys.projectBoard(Project.defaultId)).value =
        '{not json';
    expect(vm.summary(Project.defaultId), isNull);
  });

  test('duplicate copies the board and leaves the source untouched', () {
    final before = stores
        .board(StorageKeys.projectBoard(Project.defaultId))
        .value;
    expect(vm.duplicate(Project.defaultId, 'Copy'), isTrue);
    expect(vm.projects.map((p) => p.name), ['My project', 'Copy']);

    final copy = vm.projects.last;
    expect(stores.board(copy.boardKey).value, before);
    expect(
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value,
      before,
    );
    expect(vm.summary(copy.id), (blocks: 2, processes: 1, arrows: 1));
    // The copy is a separate board, not the newly active one.
    expect(vm.planner, isNull);

    expect(vm.open(copy.id), isTrue);
    vm.planner!.addNode();
    vm.flush();
    expect(
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value,
      before,
    );
  });

  test('a failed board copy adds no project to the catalog', () {
    final catalogBefore = stores.catalog.value;
    // Every board key opened from here on rejects writes.
    stores.failNewBoards = true;
    expect(vm.duplicate(Project.defaultId, 'Copy'), isFalse);
    expect(vm.projects.length, 1);
    expect(stores.catalog.value, catalogBefore);
  });

  test('summaries refresh after the board changes', () {
    expect(vm.summary(Project.defaultId)!.blocks, 2);
    expect(vm.open(Project.defaultId), isTrue);
    vm.planner!.addNode();
    vm.flush();
    expect(vm.showProjects(), isTrue);
    expect(vm.summary(Project.defaultId)!.blocks, 3);
  });
}
