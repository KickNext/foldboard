import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/data/repositories/board_store.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sample_board.dart';

Map<String, dynamic> call(
  PlannerViewModel vm,
  String name, [
  Map<String, dynamic> args = const {},
]) => vm.handleTool(name, args);

class MemoryStore implements BoardStore {
  String? value;
  bool fail = false;
  int writes = 0;
  @override
  String? read() => value;
  @override
  void write(String json) {
    if (fail) throw StateError('Storage full');
    value = json;
    writes++;
  }
}

void main() {
  test('agent edits a minimal board, searches and exports a complete area', () {
    final repo = sampleBoard();
    final vm = PlannerViewModel(repository: repo);
    addTearDown(vm.dispose);
    expect(
      call(vm, 'apply-changes', {
        'expectedRevision': repo.revision,
        'changes': {
          'nodes': [
            {'id': 'core-service', 'description': 'Updated order flow'},
          ],
        },
      })['ok'],
      isTrue,
    );
    expect(
      call(vm, 'search-architecture', {'query': 'Updated order'})['results'],
      hasLength(1),
    );
    final area =
        call(vm, 'get-area', {'id': 'core-domain', 'return': 'full'})['area']
            as Map<String, dynamic>;
    expect(area.containsKey('dataModels'), isFalse);
    expect(area.containsKey('ports'), isFalse);
    expect(area.containsKey('contracts'), isFalse);
    final imported = ArchitectureRepository()..replace(area);
    expect(imported.nodes, isNotEmpty);
    final export = call(vm, 'export-architecture');
    expect(export['format'], 'json');
    expect(export['content'], export['json']);
    final roundTrip = ArchitectureRepository()
      ..replace(jsonDecode(export['json'] as String) as Map<String, dynamic>);
    expect(
      roundTrip.nodes.map((n) => n.toJson()),
      repo.nodes.map((n) => n.toJson()),
    );
    final markdown = call(vm, 'export-architecture', {'format': 'markdown'});
    expect(markdown['filename'], 'foldboard.md');
    expect(markdown['content'], markdown['markdown']);
    expect(markdown['markdown'], contains('## Connections'));
    expect(markdown['markdown'], isNot(contains('core-service')));
    final editableMarkdown = call(vm, 'export-architecture', {
      'format': 'markdown',
      'includeIds': true,
    });
    expect(editableMarkdown['markdown'], contains('core-service'));
    expect(
      call(vm, 'export-architecture', {'format': 'xml'})['code'],
      'invalid-arguments',
    );
    expect(call(vm, 'add-port', {})['ok'], isFalse);
  });

  test('invalid batch and stale revision never partially alter a board', () {
    final vm = PlannerViewModel(repository: sampleBoard());
    addTearDown(vm.dispose);
    final before = vm.prettyJson;
    expect(
      call(vm, 'apply-changes', {
        'changes': {
          'nodes': [
            {'id': 'core-service', 'title': 'Must not persist'},
          ],
          'edges': [
            {'id': 'bad', 'from': 'core-service', 'to': 'missing'},
          ],
        },
      })['ok'],
      isFalse,
    );
    expect(vm.prettyJson, before);
    expect(
      call(vm, 'apply-changes', {
        'expectedRevision': -1,
        'changes': {
          'deleteIds': ['core-service'],
        },
      })['ok'],
      isFalse,
    );
    expect(vm.prettyJson, before);
    expect(
      call(vm, 'apply-changes', {
        'changes': {
          'groups': [
            {'id': 'commerce-platform', 'parentId': 'core-domain'},
          ],
        },
      })['ok'],
      isFalse,
    );
    expect(vm.prettyJson, before);
  });

  test('apply-changes warns when newly created cards are not connected', () {
    final repo = sampleBoard();
    final vm = PlannerViewModel(repository: repo);
    addTearDown(vm.dispose);

    final dryRun = call(vm, 'apply-changes', {
      'validate': true,
      'changes': {
        'nodes': [
          {'id': 'orphan', 'title': 'Orphan'},
        ],
      },
    });
    expect(dryRun['warnings'], [
      {
        'code': 'unconnected-card',
        'severity': 'warning',
        'ids': ['orphan'],
      },
    ]);
    expect(repo.nodes.any((node) => node.id == 'orphan'), isFalse);

    final connected = call(vm, 'apply-changes', {
      'changes': {
        'nodes': [
          {'id': 'next-step', 'title': 'Next step'},
        ],
        'edges': [
          {'id': 'client-next', 'from': 'web-client', 'to': 'next-step'},
        ],
      },
    });
    expect(connected['warnings'], isEmpty);

    final written = call(vm, 'apply-changes', {
      'changes': {
        'nodes': [
          {'id': 'orphan', 'title': 'Orphan'},
        ],
      },
    });
    expect(written['warnings'], [
      {
        'code': 'unconnected-card',
        'severity': 'warning',
        'ids': ['orphan'],
      },
    ]);
  });

  test('deletion cleans arrows and reparents nested areas', () {
    final repo = sampleBoard();
    repo.applyChanges({
      'deleteIds': ['core-domain'],
    });
    expect(
      repo.nodes.firstWhere((n) => n.id == 'core-service').parentId,
      'commerce-platform',
    );
    repo.applyChanges({
      'deleteIds': ['core-service'],
    });
    expect(repo.edges, isEmpty);
  });

  test(
    'empty, duplicate and invalid numeric values are rejected atomically',
    () {
      final repo = sampleBoard();
      final before = jsonEncode(repo.snapshot());
      for (final changes in <Map<String, dynamic>>[
        {
          'nodes': [
            {'id': '', 'title': 'Bad'},
          ],
        },
        {
          'nodes': [
            {'id': 'core-service'},
            {'id': 'core-service'},
          ],
        },
        {
          'groups': [
            {'id': 'core-domain', 'width': -1},
          ],
        },
        {
          'nodes': [
            {'id': 'core-service', 'x': double.infinity},
          ],
        },
        {
          'nodes': [
            {
              'id': 'core-service',
              'dataModelIds': ['missing'],
            },
          ],
        },
      ]) {
        expect(
          () => repo.applyChanges(changes),
          throwsA(isA<FormatException>()),
        );
        expect(jsonEncode(repo.snapshot()), before);
      }
    },
  );

  test('browser persistence round trips and reports failed saves', () {
    final store = MemoryStore();
    final repo = ArchitectureRepository(store: store);
    repo.replace(sampleBoard().snapshot());
    expect(repo.pendingSave, isTrue);
    repo.flush();
    expect(repo.pendingSave, isFalse);
    final restored = ArchitectureRepository(store: store);
    expect(
      restored.nodes.map((n) => n.toJson()),
      repo.nodes.map((n) => n.toJson()),
    );
    store.fail = true;
    repo.applyChanges({
      'nodes': [
        {'id': 'core-service', 'title': 'Changed'},
      ],
    });
    repo.flush();
    expect(repo.storageError, isNotNull);
    expect(repo.pendingSave, isTrue);
    store.fail = false;
    repo.flush();
    expect(repo.storageError, isNull);
    repo.dispose();
    restored.dispose();
  });

  test('corrupt saved data is not silently replaced by an empty board', () {
    final store = MemoryStore()..value = '{broken';
    final repo = ArchitectureRepository(store: store);
    expect(repo.storageError, isNotNull);
    expect(() => repo.clear(), throwsStateError);
    repo.dispose();
    expect(store.value, '{broken');
    expect(store.writes, 0);
  });
}
