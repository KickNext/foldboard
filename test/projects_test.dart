import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/examples/example_project.dart';
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
        {'id': 'original', 'title': 'Original'},
      ],
    });
    vm = ProjectsViewModel(repository: stores.repository());
  });
  tearDown(() {
    vm.dispose();
    vm.repository.dispose();
  });

  test('existing board becomes first project without rewriting it', () {
    final before = stores
        .board(StorageKeys.projectBoard(Project.defaultId))
        .value;
    expect(vm.projects.single.name, 'My project');
    expect(vm.open(Project.defaultId), isTrue);
    expect(vm.planner!.nodes.single.id, 'original');
    expect(
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value,
      before,
    );
    expect(vm.rename(Project.defaultId, 'Original project'), isTrue);
    expect(vm.planner!.nodes.single.id, 'original');
    expect(
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value,
      before,
    );
  });

  test('example is separate, idempotent, and keeps browser edits', () {
    final original = stores
        .board(StorageKeys.projectBoard(Project.defaultId))
        .value;

    expect(vm.openExample(), isTrue);
    expect(vm.activeProject!.id, exampleProjectId);
    expect(vm.activeProject!.name, exampleProjectName);
    expect(vm.projects, hasLength(2));
    expect(vm.planner!.nodes, hasLength(9));
    expect(vm.planner!.groups, hasLength(2));
    expect(vm.planner!.edges, hasLength(9));
    expect(
      stores.board(StorageKeys.projectBoard(Project.defaultId)).value,
      original,
    );

    vm.planner!.addNode(title: 'My note');
    expect(vm.showProjects(), isTrue);
    expect(vm.openExample(), isTrue);

    expect(vm.projects.where((p) => p.id == exampleProjectId), hasLength(1));
    expect(vm.planner!.nodes.any((node) => node.title == 'My note'), isTrue);
  });

  test(
    'switch flushes pending changes and each board survives reload separately',
    () {
      vm.open(Project.defaultId);
      vm.planner!.addNode(title: 'Pending original');
      expect(vm.create('Second'), isTrue);
      final secondId = vm.activeProject!.id;
      expect(vm.planner!.nodes, isEmpty);
      vm.planner!.addNode(title: 'Only second');
      expect(vm.open(Project.defaultId), isTrue);
      expect(vm.planner!.nodes.map((n) => n.title), [
        'Original',
        'Pending original',
      ]);
      vm.open(secondId);
      expect(vm.planner!.nodes.single.title, 'Only second');
      vm.flush();
      final reloaded = ProjectsViewModel(repository: stores.repository());
      expect(reloaded.activeProject!.id, secondId);
      expect(reloaded.planner!.nodes.single.title, 'Only second');
      reloaded.dispose();
      reloaded.repository.dispose();
    },
  );

  test(
    'save failure keeps the board and pending edits open, retry succeeds',
    () {
      vm.open(Project.defaultId);
      final current = vm.planner;
      stores.board(StorageKeys.projectBoard(Project.defaultId)).failWrite =
          true;
      vm.planner!.addNode(title: 'Unsaved');
      expect(vm.create('Blocked'), isFalse);
      expect(vm.showProjects(), isFalse);
      expect(vm.planner, same(current));
      expect(vm.planner!.nodes, hasLength(2));
      expect(vm.projects, hasLength(1));
      expect(vm.warning, isNotNull);
      stores.board(StorageKeys.projectBoard(Project.defaultId)).failWrite =
          false;
      expect(vm.showProjects(), isTrue);
      expect(vm.warning, isNull);
      expect(vm.planner, isNull);
      vm.open(Project.defaultId);
      expect(vm.planner!.nodes, hasLength(2));
    },
  );

  test('catalog failures never commit a rename, create or switch', () {
    vm.open(Project.defaultId);
    stores.catalog.failWrite = true;
    expect(vm.rename(Project.defaultId, 'Lost name'), isFalse);
    expect(vm.create('Lost project'), isFalse);
    expect(vm.showProjects(), isFalse);
    expect(vm.projects.single.name, 'My project');
    expect(vm.activeProject!.id, Project.defaultId);
    expect(vm.planner!.nodes.single.id, 'original');
  });

  test(
    'corrupt catalog is protected from being replaced with an empty catalog',
    () {
      stores.catalog.value = '{bad-json';
      final repo = stores.repository();
      expect(repo.storageError, StorageFailure.read);
      expect(repo.canEdit, isFalse);
      expect(() => repo.create('Wrong recovery'), throwsStateError);
      expect(stores.catalog.value, '{bad-json');
      repo.dispose();
    },
  );

  test('a corrupt board cannot replace the currently open board', () {
    vm.create('Second');
    final second = vm.activeProject!;
    vm.open(Project.defaultId);
    stores.board(second.boardKey).value = '{bad';
    expect(vm.open(second.id), isFalse);
    expect(vm.activeProject!.id, Project.defaultId);
    expect(vm.planner!.nodes.single.id, 'original');
    expect(stores.board(second.boardKey).value, '{bad');
  });

  test('names are trimmed, blank names rejected, identical names keep distinct IDs', () {
    expect(vm.create('   '), isFalse);
    expect(vm.create('  Shared name  '), isTrue);
    final first = vm.activeProject!.id;
    expect(vm.activeProject!.name, 'Shared name');
    expect(vm.create('Shared name'), isTrue);
    expect(vm.activeProject!.id, isNot(first));
  });

  test(
    'WebMCP tools are scoped to active project and reject stale project IDs',
    () {
      Map<String, dynamic> call(
        String tool, [
        Map<String, dynamic> args = const {},
      ]) => vm.handleTool(tool, args);
      expect(call('get-architecture')['ok'], isFalse);
      expect(call('list-projects')['projects'], hasLength(1));
      expect(call('open-project', {'id': Project.defaultId})['ok'], isTrue);
      expect(call('get-architecture')['project']['id'], Project.defaultId);
      expect(call('create-project', {'name': 'Agent project'})['ok'], isTrue);
      final created = vm.activeProject!.id;
      final changes = {
        'nodes': [
          {'id': 'agent-node', 'title': 'Agent block'},
        ],
      };
      expect(
        call('apply-changes', {
          'projectId': Project.defaultId,
          'changes': changes,
        })['ok'],
        isFalse,
      );
      expect(vm.planner!.nodes, isEmpty);
      expect(
        call('apply-changes', {'projectId': created, 'changes': changes})['ok'],
        isTrue,
      );
      expect(call('export-architecture')['json'], contains('Agent block'));
      call('open-project', {'id': Project.defaultId});
      expect(vm.planner!.nodes.single.id, 'original');
    },
  );

  test('create-project retries return the original project after reload', () {
    Map<String, dynamic> invoke(
      String tool, [
      Map<String, dynamic> args = const {},
    ]) => vm.handleTool(tool, args);

    final args = {
      'name': 'Reliable agent project',
      'clientRequestId': 'run-42',
    };
    final first = invoke('create-project', args);
    final id = first['project']['id'];
    expect(first['replayed'], isFalse);
    expect(vm.projects, hasLength(2));

    final retry = invoke('create-project', args);
    expect(retry['replayed'], isTrue);
    expect(retry['project']['id'], id);
    expect(vm.projects, hasLength(2));

    vm.dispose();
    vm.repository.dispose();
    vm = ProjectsViewModel(repository: stores.repository());
    final afterReload = invoke('create-project', args);
    expect(afterReload['replayed'], isTrue);
    expect(afterReload['project']['id'], id);
    expect(vm.projects, hasLength(2));
    expect(
      invoke('create-project', {...args, 'name': 'Different name'})['code'],
      'idempotency-conflict',
    );
  });
}
