import 'dart:convert';
import 'dart:math';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/agent_protocol.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agent_protocol_test.dart' show call;
import 'level_navigation_test.dart' show processBoard;

Map<String, dynamic> replay(Map<String, dynamic> before, Map patch) {
  final result = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
  for (final key in ['nodes', 'groups', 'edges']) {
    final rows = {
      for (final row in result[key] as List? ?? []) row['id']: row as Map,
    };
    for (final id in patch['deleteIds'] as List? ?? []) {
      rows.remove(id);
    }
    for (final row in patch[key] as List? ?? []) {
      rows[row['id']] = {...?rows[row['id']], ...row as Map};
    }
    result[key] = rows.values.toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  }
  if (patch.containsKey('referencePositions')) {
    result['referencePositions'] = patch['referencePositions'];
  }
  result.remove('revision');
  return result;
}

void main() {
  test('Unicode search offsets and truncation preserve valid text', () {
    final repo = ArchitectureRepository();
    final vm = PlannerViewModel(repository: repo, registerBridge: false);
    addTearDown(vm.dispose);
    addTearDown(repo.dispose);
    repo.replace({
      'nodes': [
        {
          'id': 'unicode',
          'title': '${'x' * 159}😀',
          'description': '${'İ' * 600} needle 😀',
        },
      ],
    });
    final found = call(vm, 'search-architecture', {'query': 'needle'});
    expect(found['ok'], isTrue);
    expect(found['results'][0]['snippet'], contains('needle'));
    expect(found['results'][0]['title'], 'x' * 159);
    expect(
      call(vm, 'get-area', {
        'id': 'unicode',
        'descriptionLimit': 0,
      })['area']['nodes'][0].containsKey('description'),
      isFalse,
    );
  });
  for (final size in [200, 1000]) {
    test('$size cards: area/search/root responses have bounded budgets', () {
      final repo = ArchitectureRepository();
      final vm = PlannerViewModel(repository: repo, registerBridge: false);
      addTearDown(vm.dispose);
      addTearDown(repo.dispose);
      repo.replace({
        'nodes': [
          for (var i = 0; i < size; i++)
            {
              'id': 'n$i',
              'title': 'Card $i',
              'description': '${'long text ' * 500}needle',
            },
        ],
        'edges': [
          for (var i = 1; i < size; i++)
            {'id': 'e$i', 'from': 'n0', 'to': 'n$i'},
        ],
      });
      final before = vm.prettyJson;
      final one = call(vm, 'get-area', {'id': 'n0'});
      expect(one['ok'], isTrue);
      expect(one['area']['nodes'], hasLength(1));
      expect(one.containsKey('view'), isFalse);
      expect(one['area']['nodes'][0].containsKey('x'), isFalse);
      expect(one['area']['nodes'][0]['descriptionTruncated'], isTrue);
      expect(one['area']['edges'], hasLength(20));
      expect(one['totalEdges'], size - 1);
      expect(one['nextEdgeOffset'], 20);
      expect(jsonEncode(one).length, lessThan(2400));
      final nextEdges = call(vm, 'get-area', {'id': 'n0', 'edgeOffset': 20});
      expect(nextEdges['area']['edges'][0]['id'], 'e21');
      final root = call(vm, 'get-area');
      expect(root['total'], size);
      expect(root['nextOffset'], 20);
      expect(root['area']['nodes'], hasLength(20));
      expect(jsonEncode(root).length, lessThan(16000));
      final search = call(vm, 'search-architecture', {'query': 'needle'});
      expect(search['total'], size);
      expect(search['nextOffset'], 20);
      expect(search['results'], hasLength(20));
      expect(search['results'][0]['snippet'], contains('needle'));
      expect(search['results'][0].containsKey('description'), isFalse);
      expect(jsonEncode(search).length, lessThan(8000));
      final second = call(vm, 'search-architecture', {
        'query': 'needle',
        'offset': 20,
      });
      expect(second['results'][0]['id'], 'n20');
      final full = call(vm, 'get-area', {'return': 'full'});
      expect(full['area']['nodes'], hasLength(size));
      expect(
        jsonEncode(full).length,
        greaterThan(jsonEncode(one).length * 100),
      );
      expect(vm.prettyJson, before);
      // Reproducible payload measurements, not tokenizer-dependent claims.
      printOnFailure(
        'Budget $size: area=${jsonEncode(one).length}, root=${jsonEncode(root).length}, search=${jsonEncode(search).length}, full=${jsonEncode(full).length} chars',
      );
    });
  }

  test(
    'area depth, paging and explicit full fields do not change navigation',
    () {
      final repo = processBoard();
      final vm = PlannerViewModel(repository: repo, registerBridge: false);
      addTearDown(vm.dispose);
      addTearDown(repo.dispose);
      final area = call(vm, 'get-area', {'id': 'app'});
      expect(area['depthTruncated'], isTrue);
      expect((area['area']['nodes'] as List).map((n) => n['id']), ['ui']);
      final deep = call(vm, 'get-area', {
        'id': 'app',
        'maxDepth': 2,
        'includeCoordinates': true,
      });
      expect(deep['depthTruncated'], isFalse);
      expect(deep['area']['nodes'], hasLength(2));
      expect(deep['area']['nodes'][0].containsKey('x'), isTrue);
      final first = call(vm, 'get-area', {'id': 'app', 'limit': 1});
      final second = call(vm, 'get-area', {
        'id': 'app',
        'limit': 1,
        'offset': 1,
      });
      expect(first['area']['groups'][0]['id'], 'app');
      expect(second['area']['nodes'][0]['id'], 'ui');
      final full = call(vm, 'get-area', {
        'id': 'app',
        'return': 'full',
        'includeView': true,
      });
      expect(full['view']['levelId'], 'app');
      expect(vm.currentLevelId, isNull);
      for (final args in [
        {'limit': 0},
        {'limit': 101},
        {'edgeLimit': 0},
        {'maxDepth': 9},
        {'descriptionLimit': -1},
        {'includeView': 'yes'},
      ]) {
        expect(call(vm, 'get-area', args)['code'], 'invalid-arguments');
      }
      expect(
        call(vm, 'search-architecture', {'query': '', 'limit': 101})['code'],
        'invalid-arguments',
      );
      expect(
        call(vm, 'get-changes', {
          'sinceRevision': repo.revision,
          'mode': 'unknown',
        })['code'],
        'invalid-arguments',
      );
    },
  );

  test(
    'compact diff reconstructs edits, undo, redo, deletion and ID type reuse',
    () {
      final repo = processBoard();
      final vm = PlannerViewModel(repository: repo, registerBridge: false);
      addTearDown(vm.dispose);
      addTearDown(repo.dispose);
      final before = repo.snapshot();
      final start = repo.revision;
      repo.applyChanges({
        'nodes': [
          {'id': 'ui', 'title': 'New title'},
        ],
      });
      repo.undo();
      repo.redo();
      repo.applyChanges({
        'deleteIds': ['app'],
      });
      repo.replace({
        'groups': [
          {'id': 'human', 'title': 'Now process'},
        ],
        'nodes': [
          {'id': 'ui', 'title': 'Recreated'},
        ],
      });
      final result = call(vm, 'get-changes', {
        'sinceRevision': start,
        'historyId': repo.historyId,
      });
      expect(result.containsKey('changes'), isFalse);
      expect(replay(before, result['patch']), replay(repo.snapshot(), {}));
      final events = call(vm, 'get-changes', {
        'sinceRevision': start,
        'mode': 'events',
      });
      expect(events['changes'], hasLength(5));
      expect(
        call(vm, 'get-changes', {'sinceRevision': repo.revision})['patch'],
        isEmpty,
      );
    },
  );

  test('100 moves collapse to a single row; composed patches do not mutate journal', () {
    final repo = processBoard();
    final vm = PlannerViewModel(repository: repo, registerBridge: false);
    addTearDown(vm.dispose);
    addTearDown(repo.dispose);
    final start = repo.revision;
    for (var i = 0; i < 100; i++) {
      repo.applyChanges({
        'nodes': [
          {'id': 'ui', 'x': i + 1000},
        ],
      });
    }
    final args = {'sinceRevision': start, 'mode': 'events'};
    final before = jsonEncode(call(vm, 'get-changes', args));
    final compact = call(vm, 'get-changes', {'sinceRevision': start});
    expect(compact['patch']['nodes'], [
      {'id': 'ui', 'x': 1099.0},
    ]);
    expect(jsonEncode(compact).length, lessThan(600));
    expect(before.length, greaterThan(jsonEncode(compact).length * 10));
    expect(jsonEncode(call(vm, 'get-changes', args)), before);
  });

  test('random delete/recreate/type-switch streams compose losslessly', () {
    final random = Random(17);
    final initial = <String, dynamic>{
      'nodes': [
        {'id': 'a', 'title': 'Initial', 'x': 3},
      ],
      'groups': [],
      'edges': [],
      'referencePositions': {},
    };
    for (var run = 0; run < 80; run++) {
      var state = replay(initial, {});
      final patches = <Map<String, dynamic>>[];
      for (var i = 0; i < 30; i++) {
        final id = ['a', 'b', 'c'][random.nextInt(3)];
        final patch = <String, dynamic>{};
        if (random.nextBool()) patch['deleteIds'] = [id];
        if (random.nextBool()) {
          patch['deleteIds'] = [id];
          patch[['nodes', 'groups', 'edges'][random.nextInt(3)]] = [
            {'id': id, 'title': 'v$i', 'x': i},
          ];
        }
        if (random.nextInt(5) == 0) {
          patch['referencePositions'] = {
            'level': {
              'a': {'x': i, 'y': 0},
            },
          };
        }
        patches.add(patch);
        state = replay(state, patch);
      }
      final encoded = jsonEncode(patches);
      expect(replay(initial, composePatches(patches)), state);
      expect(jsonEncode(patches), encoded);
    }
  });
}
