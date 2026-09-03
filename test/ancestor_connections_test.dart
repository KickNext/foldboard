import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/domain/models/architecture_models.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

void main() {
  for (final (from, to) in [
    ('ui', 'app'),
    ('app', 'ui'),
    ('api', 'app'),
    ('app', 'api'),
    ('inner', 'app'),
    ('app', 'inner'),
    ('api', 'inner'),
    ('inner', 'api'),
  ]) {
    test(
      'reject ancestor arrow $from -> $to atomically, including WebMCP/import',
      () {
        final repo = processBoard();
        final vm = PlannerViewModel(repository: repo, registerBridge: false);
        addTearDown(() {
          vm.dispose();
          repo.dispose();
        });
        final before = vm.prettyJson;
        final edge = {'id': 'bad', 'from': from, 'to': to};
        expect(
          () => repo.applyChanges({
            'edges': [edge],
          }),
          throwsA(isA<AncestorConnectionException>()),
        );
        expect(vm.prettyJson, before);
        expect(
          repo.addEdge(ArchitectureEdge(id: 'bad', from: from, to: to)),
          isFalse,
        );
        final imported = repo.snapshot();
        (imported['edges'] as List).add(edge);
        expect(
          () => vm.readImport(jsonEncode(imported)),
          throwsA(isA<AncestorConnectionException>()),
        );
        for (final replace in [false, true]) {
          final result = jsonDecode(
            vm.handleToolCall(
              jsonEncode({
                'tool': 'apply-changes',
                'args': {
                  'replace': replace,
                  'changes': replace
                      ? imported
                      : {
                          'edges': [edge],
                        },
                },
              }),
            ),
          );
          expect(result['ok'], isFalse);
          expect(result['error'], contains('containing process'));
        }
        vm.startConnection(from);
        vm.completeConnection(to);
        expect(vm.connectFrom, from);
        expect(vm.warning, vm.strings.ancestorConnection);
        expect(vm.prettyJson, before);
        vm.cancelConnection();
        expect(vm.warning, isNull);
      },
    );
  }

  test('siblings, external actors, and cycles between peers are allowed', () {
    final repo = processBoard();
    addTearDown(repo.dispose);
    repo.applyChanges({
      'edges': [
        {'id': 'external', 'from': 'human', 'to': 'app'},
        {'id': 'peer', 'from': 'ui', 'to': 'inner'},
        {'id': 'reverse', 'from': 'inner', 'to': 'ui'},
      ],
    });
    expect(repo.edges, hasLength(6));
  });

  test(
    'changing hierarchy cannot turn a valid arrow into an ancestor arrow',
    () {
      final repo = processBoard();
      addTearDown(repo.dispose);
      repo.applyChanges({
        'edges': [
          {'id': 'outside', 'from': 'human', 'to': 'app'},
        ],
      });
      final before = jsonEncode(repo.snapshot());
      expect(
        () => repo.applyChanges({
          'nodes': [
            {'id': 'human', 'parentId': 'app'},
          ],
        }),
        throwsA(isA<AncestorConnectionException>()),
      );
      expect(jsonEncode(repo.snapshot()), before);
      // A single transaction can remove the conflicting edge and move the card.
      repo.applyChanges({
        'nodes': [
          {'id': 'human', 'parentId': 'app'},
        ],
        'deleteIds': ['outside'],
      });
      expect(repo.nodes.first.parentId, 'app');
    },
  );

  test('a saved document with an ancestor arrow is rejected on load', () {
    final seed = processBoard();
    final doc = seed.snapshot();
    seed.dispose();
    (doc['edges'] as List).add({'id': 'old', 'from': 'ui', 'to': 'app'});
    final store = MemoryProjectStore()..value = jsonEncode(doc);
    final original = store.value;
    final repo = ArchitectureRepository(store: store);
    addTearDown(repo.dispose);
    expect(repo.storageError, isNotNull);
    expect(repo.edges, isEmpty);
    expect(() => repo.clear(), throwsStateError);
    expect(store.value, original);
  });
}
