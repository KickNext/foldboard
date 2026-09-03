import 'dart:convert';

import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/data/repositories/settings_repository.dart';
import 'package:foldboard/domain/models/app_settings.dart';
import 'package:foldboard/domain/models/agent_protocol.dart';
import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/widgets/architecture_canvas.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'level_navigation_test.dart' show processBoard;
import 'support/project_stores.dart';

Map<String, dynamic> call(
  PlannerViewModel vm,
  String name, [
  Map<String, dynamic> args = const {},
]) =>
    jsonDecode(vm.handleToolCall(jsonEncode({'tool': name, 'args': args})))
        as Map<String, dynamic>;

void main() {
  late ArchitectureRepository repo;
  late PlannerViewModel vm;
  setUp(() {
    repo = processBoard();
    vm = PlannerViewModel(repository: repo, registerBridge: false);
  });
  tearDown(() {
    vm.dispose();
    repo.dispose();
  });

  test(
    'reference position changes report only moved or removed references',
    () {
      final before = {
        'referencePositions': {
          'app': {
            'human': {'x': 10, 'y': 20},
            'api': {'x': 30, 'y': 40},
          },
        },
      };
      final after = {
        'referencePositions': {
          'app': {
            'human': {'x': 15, 'y': 20},
            'api': {'x': 30, 'y': 40},
          },
        },
      };
      expect(affectedIds(documentDiff(before, after), before: before), [
        'human',
      ]);
      final removed = documentDiff(before, {});
      expect(removed['referencePositions'], isEmpty);
      expect(affectedIds(removed, before: before), ['api', 'human']);
    },
  );

  test('drag journal stores the exact changed axes', () {
    final start = repo.revision;
    repo.setNodePosition('human', const Offset(220, 300));
    final events = call(vm, 'get-changes', {
      'sinceRevision': start,
      'mode': 'events',
    })['changes'];
    expect(events[0]['patch'], {
      'nodes': [
        {'id': 'human', 'x': 220.0},
      ],
    });
  });

  test('a full import changing card type produces a lossless ordered diff', () {
    final before = repo.snapshot();
    final start = repo.revision;
    repo.replace({
      'groups': [
        {'id': 'human', 'title': 'Now a process'},
      ],
    });
    final patch =
        call(vm, 'get-changes', {
              'sinceRevision': start,
              'mode': 'events',
            })['changes'][0]['patch']
            as Map;
    final deleted = (patch['deleteIds'] as List).toSet();
    for (final key in ['nodes', 'groups', 'edges']) {
      final rows = {
        for (final row in before[key] as List)
          if (!deleted.contains(row['id'])) row['id']: row,
      };
      for (final row in patch[key] as List? ?? []) {
        rows[row['id']] = {...?rows[row['id']] as Map?, ...row as Map};
      }
      expect(rows.values.toList(), repo.snapshot()[key]);
    }
  });

  test('outline is a names/counts tree and marks omitted branches', () {
    final result = call(vm, 'get-outline');
    expect(result['totals'], {'blocks': 3, 'processes': 2, 'arrows': 3});
    expect(result['outline']['children'][0]['children'][0]['id'], 'inner');
    final text = jsonEncode(result);
    expect(text, isNot(contains('description')));
    expect(text, isNot(contains('"x":')));
    final shallow = call(vm, 'get-outline', {'maxDepth': 0});
    expect(shallow['outline']['truncated'], isTrue);
    expect(shallow['outline'].containsKey('children'), isFalse);
  });

  test('200-card mutation summary stays small; full is explicit', () {
    repo.replace({
      'nodes': [
        for (var i = 0; i < 220; i++)
          {
            'id': 'n$i',
            'title': 'Card $i',
            'description': 'Long description. ' * 50,
          },
      ],
    });
    final result = call(vm, 'apply-changes', {
      'changes': {
        'nodes': [
          {'id': 'n0', 'title': 'Edited'},
        ],
      },
    });
    expect(result['affectedIds'], ['n0']);
    expect(result.containsKey('architecture'), isFalse);
    expect(jsonEncode(result).length, lessThan(600));
    expect(
      jsonEncode(call(vm, 'get-architecture')).length,
      greaterThan(jsonEncode(result).length * 100),
    );
    final full = call(vm, 'apply-changes', {
      'return': 'full',
      'changes': {
        'nodes': [
          {'id': 'n1', 'title': 'Edited too'},
        ],
      },
    });
    expect(full['architecture']['nodes'], hasLength(220));
    final arranged = call(vm, 'auto-arrange');
    expect(arranged['ok'], isTrue);
    expect(arranged.containsKey('architecture'), isFalse);
    expect(arranged['affectedIds'], isA<List>());
  });

  test('sparse changes accept full-document metadata without changing it', () {
    final revision = repo.revision;
    final changes = {
      'revision': revision,
      'nodes': [
        {'id': 'ui', 'title': 'Metadata-safe edit'},
      ],
    };
    final preview = call(vm, 'apply-changes', {
      'validate': true,
      'expectedRevision': revision,
      'changes': changes,
    });
    expect(preview['validated'], isTrue);
    expect(preview['wouldChange'], isTrue);
    expect(repo.revision, revision);

    final committed = call(vm, 'apply-changes', {
      'expectedRevision': revision,
      'changes': changes,
    });
    expect(committed['ok'], isTrue);
    expect(repo.snapshot().containsKey('version'), isFalse);
    expect(repo.revision, revision + 1);
    expect(
      repo.nodes.firstWhere((node) => node.id == 'ui').title,
      'Metadata-safe edit',
    );
    expect(
      call(vm, 'apply-changes', {
        'validate': true,
        'changes': {'version': 9},
      })['code'],
      'invalid-arguments',
    );
  });

  test(
    'diffs include sparse human edits, Undo, Redo and deletion side effects',
    () {
      final start = repo.revision;
      repo.applyChanges({
        'nodes': [
          {'id': 'ui', 'title': 'Changed'},
        ],
      });
      repo.undo();
      repo.redo();
      repo.applyChanges({
        'deleteIds': ['app'],
      });
      final result = call(vm, 'get-changes', {
        'sinceRevision': start,
        'historyId': repo.historyId,
        'mode': 'events',
      });
      final events = result['changes'] as List;
      expect(events, hasLength(4));
      expect(events[0]['patch'], {
        'nodes': [
          {'id': 'ui', 'title': 'Changed'},
        ],
      });
      expect(events[1]['patch']['nodes'][0]['title'], 'Editor');
      expect(events[2]['patch']['nodes'][0]['title'], 'Changed');
      expect(events[3]['patch']['deleteIds'], ['app']);
      expect(events[3]['patch']['nodes'][0]['parentId'], isNull);
      expect(events[3]['patch']['groups'][0]['parentId'], isNull);
      expect(
        call(vm, 'get-changes', {'sinceRevision': repo.revision})['patch'],
        isEmpty,
      );
    },
  );

  test('history expires explicitly by session, count and size', () {
    final start = repo.revision;
    expect(
      call(vm, 'get-changes', {
        'sinceRevision': start,
        'historyId': 'another',
      })['code'],
      'history-expired',
    );
    for (var i = 0; i < 130; i++) {
      repo.applyChanges({
        'nodes': [
          {'id': 'ui', 'title': 'Revision $i'},
        ],
      });
    }
    expect(
      call(vm, 'get-changes', {'sinceRevision': start})['code'],
      'history-expired',
    );
    final current = repo.revision;
    repo.applyChanges({
      'nodes': [
        {'id': 'ui', 'description': 'x' * 1000001},
      ],
    });
    expect(
      call(vm, 'get-changes', {'sinceRevision': current})['code'],
      'history-expired',
    );
    expect(
      call(vm, 'get-changes', {'sinceRevision': repo.revision + 1})['code'],
      'revision-conflict',
    );
  });

  test(
    'context reads do not navigate; reveal selects and focuses explicitly',
    () {
      vm.openLevel('app');
      vm.select('ui');
      vm.readViewport = () => {
        'x': 10,
        'y': 20,
        'width': 800,
        'height': 600,
        'zoom': 1,
        'visibleIds': ['ui'],
      };
      final revision = repo.revision;
      final result = call(vm, 'get-user-context');
      expect(result['context']['levelId'], 'app');
      expect(result['context']['selectedIds'], ['ui']);
      expect(result['context']['viewport']['visibleIds'], ['ui']);
      call(vm, 'get-area', {'id': 'api'});
      expect(vm.currentLevelId, 'app');
      call(vm, 'reveal-card', {'id': 'api'});
      expect(vm.currentLevelId, 'inner');
      expect(vm.selectedId, 'api');
      expect(vm.cameraTargetId, 'api');
      expect(repo.revision, revision);
    },
  );

  test('read-only blocks agent writes but allows reads, navigation and human edits', () {
    vm.agentCanWrite = () => false;
    final before = vm.prettyJson;
    for (final name in ['apply-changes', 'auto-arrange']) {
      expect(
        call(vm, name, {
          'changes': {
            'deleteIds': ['ui'],
          },
        })['code'],
        'read-only',
      );
    }
    expect(vm.prettyJson, before);
    expect(call(vm, 'get-outline')['ok'], isTrue);
    expect(call(vm, 'export-architecture')['ok'], isTrue);
    expect(call(vm, 'reveal-card', {'id': 'api'})['ok'], isTrue);
    vm.addNode(title: 'Human edit');
    expect(vm.nodes.last.title, 'Human edit');
    expect(call(vm, 'get-user-context')['context']['agentCanWrite'], isFalse);
  });

  test('typed errors preserve revision and atomicity', () {
    final before = vm.prettyJson;
    final stale = call(vm, 'apply-changes', {
      'expectedRevision': 0,
      'changes': {},
    });
    expect(stale['code'], 'revision-conflict');
    expect(stale['revision'], repo.revision);
    for (final name in [
      'get-area',
      'reveal-card',
      'export-architecture',
      'auto-arrange',
    ]) {
      expect(call(vm, name, {'id': 'missing'})['code'], 'unknown-id');
    }
    expect(
      call(vm, 'apply-changes', {
        'changes': {
          'edges': [
            {'id': 'bad', 'from': 'ui', 'to': 'app'},
          ],
        },
      })['code'],
      'ancestor-arrow',
    );
    expect(
      call(vm, 'apply-changes', {
        'changes': {
          'deleteIds': ['missing'],
        },
      })['code'],
      'unknown-id',
    );
    expect(
      call(vm, 'apply-changes', {'return': 'bad', 'changes': {}})['code'],
      'invalid-arguments',
    );
    expect(
      call(vm, 'auto-arrange', {'mode': 'bad'})['code'],
      'invalid-arguments',
    );
    expect(call(vm, 'get-changes')['code'], 'invalid-arguments');
    expect(vm.prettyJson, before);
  });

  test('linter is paginated, reports IDs, and never mutates', () {
    repo.applyChanges({
      'nodes': [
        {'id': 'orphan', 'title': 'Human'},
        {'id': 'blank', 'title': '  '},
      ],
    });
    final before = vm.prettyJson;
    final result = call(vm, 'validate-architecture', {
      'maxDepth': 1,
      'limit': 500,
    });
    final codes = (result['issues'] as List).map((i) => i['code']).toSet();
    expect(
      codes,
      containsAll([
        'unconnected-card',
        'empty-description',
        'empty-title',
        'duplicate-title',
        'deep-nesting',
      ]),
    );
    final first = call(vm, 'validate-architecture', {'limit': 1});
    expect(first['issues'], hasLength(1));
    expect(first['nextOffset'], 1);
    expect(
      call(vm, 'validate-architecture', {'limit': 0})['code'],
      'invalid-arguments',
    );
    expect(vm.prettyJson, before);
  });

  test('agent Undo is separate and cannot undo later human work', () {
    final before = vm.prettyJson;
    call(vm, 'apply-changes', {
      'changes': {
        'nodes': [
          {'id': 'ui', 'title': 'Agent'},
        ],
      },
    });
    expect(vm.agentChangedIds, contains('ui'));
    expect(vm.canUndoAgentChange, isTrue);
    vm.undoAgentChange();
    expect(repo.nodes.firstWhere((n) => n.id == 'ui').title, 'Editor');
    expect(vm.prettyJson, isNot(before)); // Undo advances revision.
    call(vm, 'apply-changes', {
      'changes': {
        'nodes': [
          {'id': 'ui', 'title': 'Agent again'},
        ],
      },
    });
    vm.addNode(title: 'Later human edit');
    expect(vm.canUndoAgentChange, isFalse);
    vm.undoAgentChange();
    expect(vm.nodes.last.title, 'Later human edit');
  });

  test('active drag rejects mutations to preserve the human undo boundary', () {
    repo.beginTransaction();
    expect(call(vm, 'apply-changes', {'changes': {}})['code'], 'user-busy');
    expect(call(vm, 'auto-arrange')['code'], 'user-busy');
    expect(call(vm, 'get-outline')['ok'], isTrue);
    repo.endTransaction();
    expect(call(vm, 'apply-changes', {'changes': {}})['ok'], isTrue);
  });

  test(
    'agent policy is persisted and applied to project creation/switching',
    () {
      final store = MemoryProjectStore();
      final settings = SettingsRepository(store: store);
      final projects = ProjectsViewModel(
        repository: ProjectStores().repository(),
      );
      addTearDown(() {
        settings.dispose();
        projects.dispose();
        projects.repository.dispose();
      });
      settings.save(const AppSettings(agentReadOnly: true));
      final restored = SettingsRepository(store: store);
      addTearDown(restored.dispose);
      expect(restored.value.agentReadOnly, isTrue);
      projects.agentCanWrite = () => !restored.value.agentReadOnly;
      Map invoke(String name, Map args) => jsonDecode(
        projects.handleToolCall(jsonEncode({'tool': name, 'args': args})),
      ) as Map;
      expect(
        invoke('create-project', {'name': 'Not allowed'})['code'],
        'read-only',
      );
      expect(invoke('open-project', {'id': Project.defaultId})['ok'], isTrue);
      expect(invoke('apply-changes', {'changes': {}})['code'], 'read-only');
      expect(invoke('open-project', {'id': 'missing'})['code'], 'unknown-id');
      expect(
        invoke('get-outline', {'projectId': 'another'})['code'],
        'project-conflict',
      );
    },
  );

  for (final width in [400.0, 1200.0]) {
    testWidgets(
      'agent feedback confirms Undo without shifting canvas at $width',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(FoldboardApp(viewModel: vm));
        await tester.pumpAndSettle();
        final canvas = find.byType(ArchitectureCanvas);
        final before = tester.getRect(canvas);
        final viewport = call(vm, 'get-user-context')['context']['viewport'];
        expect(viewport['width'], greaterThan(0));
        expect(viewport['visibleIds'], isNotEmpty);
        call(vm, 'apply-changes', {
          'changes': {
            'nodes': [
              {'id': 'human', 'title': 'Agent edit'},
            ],
          },
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.getRect(canvas), before);
        expect(find.text('Agent changed 1 item'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Undo'));
        await tester.pumpAndSettle();
        expect(find.text("Undo the agent's change?"), findsOneWidget);
        await tester.tap(find.byKey(const Key('cancel-agent-undo')));
        await tester.pumpAndSettle();
        expect(
          repo.nodes.firstWhere((n) => n.id == 'human').title,
          'Agent edit',
        );
        await tester.tap(find.widgetWithText(TextButton, 'Undo'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-agent-undo')));
        await tester.pumpAndSettle();
        expect(repo.nodes.firstWhere((n) => n.id == 'human').title, 'Human');
        expect(tester.getRect(canvas), before);
        call(vm, 'apply-changes', {
          'changes': {
            'nodes': [
              {'id': 'human', 'title': 'Agent edit again'},
            ],
          },
        });
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpAndSettle();
        expect(find.text('Agent changed 1 item'), findsNothing);
        expect(tester.getRect(canvas), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('agent-created cards are framed without zooming in', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();

    dynamic painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((widget) => widget.painter)
        .firstWhere(
          (value) => value.runtimeType.toString() == '_ViewportPainter',
        );
    final beforeScale = painter().camera.scale as double;

    call(vm, 'apply-changes', {
      'changes': {
        'nodes': [
          {
            'id': 'agent-created',
            'title': 'Created by agent',
            'x': 10000,
            'y': 5000,
          },
        ],
      },
    });
    await tester.pump();
    await tester.pump();

    final camera = painter().camera;
    final card = repo.nodes.firstWhere((node) => node.id == 'agent-created');
    final cardCenter = card.position + const Offset(130, 59);
    expect(
      camera.worldToScreen(cardCenter),
      offsetMoreOrLessEquals(camera.viewport.center(Offset.zero)),
    );
    expect(camera.scale, beforeScale);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
