import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_protocol_test.dart' show call;
import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

class CountingStore extends MemoryProjectStore {
  int writes = 0;
  @override
  void write(String json) {
    writes++;
    super.write(json);
  }
}

void main() {
  group('dry-run', () {
    late ArchitectureRepository repo;
    late PlannerViewModel vm;
    late CountingStore store;
    setUp(() {
      final seed = processBoard();
      store = CountingStore()..value = jsonEncode(seed.snapshot());
      seed.dispose();
      repo = ArchitectureRepository(store: store);
      vm = PlannerViewModel(repository: repo, registerBridge: false);
      vm.openLevel('app');
      vm.select('ui');
    });
    tearDown(() {
      vm.dispose();
      repo.dispose();
    });

    test('preview and write produce the same document; preview has zero side effects', () {
      final before = vm.prettyJson, raw = store.value;
      final context = vm.userContext();
      final revision = repo.revision;
      var signals = 0;
      vm.addListener(() => signals++);
      final changes = {
        'deleteIds': ['app'],
        'nodes': [
          {'id': 'new', 'title': 'New card'},
        ],
      };
      final result = call(vm, 'apply-changes', {
        'changes': changes,
        'expectedRevision': revision,
        'validate': true,
        'return': 'full',
      });
      expect(result['ok'], isTrue);
      expect(result['validated'], isTrue);
      expect(result['changed'], isFalse);
      expect(result['wouldChange'], isTrue);
      expect(result['affectedIds'], containsAll(['app', 'ui', 'inner', 'new']));
      expect(result['summary']['nodes']['created'], 1);
      expect(result['summary']['groups']['deleted'], 1);
      expect(vm.prettyJson, before);
      expect(vm.userContext(), context);
      expect(repo.canUndo, isFalse);
      expect(repo.pendingSave, isFalse);
      expect(vm.agentChangedIds, isEmpty);
      expect(signals, 0);
      expect(store.value, raw);
      expect(store.writes, 0);
      expect(
        call(vm, 'get-changes', {'sinceRevision': revision})['patch'],
        isEmpty,
      );
      final committed = call(vm, 'apply-changes', {
        'changes': changes,
        'expectedRevision': revision,
        'return': 'full',
      });
      final preview = result['architecture'] as Map;
      preview['revision'] = committed['revision'];
      expect(committed['architecture'], preview);
    });

    test(
      'summary never echoes large card descriptions; full preview is opt-in',
      () {
        final result = call(vm, 'apply-changes', {
          'validate': true,
          'changes': {
            'nodes': [
              {'id': 'ui', 'description': 'Long text ' * 1000},
            ],
          },
        });
        expect(result['ok'], isTrue);
        expect(jsonEncode(result).length, lessThan(1000));
        expect(result.containsKey('architecture'), isFalse);
        expect(result.containsKey('patch'), isFalse);
        expect(result['summary']['nodes']['updated'], 1);
      },
    );

    test('all batch rules use the same machine errors and stay atomic', () {
      final before = vm.prettyJson;
      for (final changes in [
        {
          'edges': [
            {'id': 'bad', 'from': 'ui', 'to': 'app'},
          ],
        },
        {
          'edges': [
            {'id': 'bad', 'from': 'ui', 'to': 'missing'},
          ],
        },
        {
          'groups': [
            {'id': 'app', 'parentId': 'inner'},
          ],
        },
        {
          'nodes': [
            {'id': 'ui', 'parentId': 'missing'},
          ],
        },
        {
          'deleteIds': ['missing'],
        },
        {
          'nodes': [
            {'id': 'ui', 'x': 'bad'},
          ],
        },
      ]) {
        final preview = call(vm, 'apply-changes', {
          'changes': changes,
          'validate': true,
        });
        final write = call(vm, 'apply-changes', {'changes': changes});
        expect(preview['ok'], isFalse);
        expect(preview['code'], write['code']);
        expect(vm.prettyJson, before);
      }
      expect(
        call(vm, 'apply-changes', {'changes': {}, 'validate': 'true'})['code'],
        'invalid-arguments',
      );
    });

    test('replace preview does not bypass ancestor restrictions or replace live state', () {
      final before = vm.prettyJson;
      final result = call(vm, 'apply-changes', {
        'changes': {
          'nodes': [
            {'id': 'only', 'title': 'Replacement'},
          ],
        },
        'replace': true,
        'validate': true,
        'return': 'full',
      });
      expect(result['architecture']['nodes'], hasLength(1));
      expect(vm.prettyJson, before);
      final bad = repo.snapshot();
      (bad['edges'] as List).add({'id': 'bad', 'from': 'ui', 'to': 'app'});
      expect(
        call(vm, 'apply-changes', {
          'changes': bad,
          'replace': true,
          'validate': true,
        })['code'],
        'ancestor-arrow',
      );
      expect(vm.prettyJson, before);
    });

    test('read-only and active drag allow previews; revision still guards later writes', () {
      vm.agentCanWrite = () => false;
      repo.beginTransaction();
      final revision = repo.revision;
      final args = {
        'changes': {
          'nodes': [
            {'id': 'ui', 'title': 'Preview'},
          ],
        },
        'expectedRevision': revision,
      };
      expect(
        call(vm, 'apply-changes', {...args, 'validate': true})['ok'],
        isTrue,
      );
      expect(call(vm, 'apply-changes', args)['code'], 'read-only');
      repo.endTransaction();
      vm.agentCanWrite = () => true;
      repo.applyChanges({
        'nodes': [
          {'id': 'human', 'title': 'Human edited'},
        ],
      });
      for (final validate in [true, false]) {
        final result = call(vm, 'apply-changes', {
          ...args,
          'validate': validate,
        });
        expect(result['code'], 'revision-conflict');
        expect(result['revision'], repo.revision);
      }
    });

    test('read-only repository can validate without touching storage', () {
      final reader = ArchitectureRepository(store: store, readOnly: true);
      final readerVm = PlannerViewModel(
        repository: reader,
        registerBridge: false,
      );
      addTearDown(() {
        readerVm.dispose();
        reader.dispose();
      });
      expect(
        call(readerVm, 'apply-changes', {
          'changes': {},
          'validate': true,
        })['wouldChange'],
        isFalse,
      );
      expect(store.writes, 0);
    });
  });
}
