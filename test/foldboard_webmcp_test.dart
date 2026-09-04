import 'dart:convert';

import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/ui/features/projects/view_models/projects_view_model.dart';
import 'package:foldboard/webmcp/foldboard_webmcp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webmcp/flutter_webmcp.dart';

import 'support/project_stores.dart';

void main() {
  test('catalog keeps the 18-tool contract in state-aware groups', () {
    final catalog = FoldboardWebMcpCatalog(
      invoke: (name, arguments) => {'ok': true},
    );

    expect(catalog.projectTools.map((tool) => tool.name), [
      'list-projects',
      'create-project',
      'open-project',
    ]);
    expect(catalog.requestTools.map((tool) => tool.name), [
      'list-requests',
      'get-request',
      'resolve-request',
    ]);
    expect(catalog.boardTools, hasLength(12));
    expect(catalog.allTools, hasLength(18));
    expect(catalog.allTools.map((tool) => tool.name).toSet(), hasLength(18));

    for (final tool in catalog.allTools) {
      expect(tool.annotations?.untrustedContent, isTrue, reason: tool.name);
      final properties = tool.inputSchema['properties'] as Map;
      expect(
        properties.containsKey('projectId'),
        !catalog.projectTools.contains(tool),
        reason: tool.name,
      );
    }
  });

  test('catalog preserves descriptions, schemas, and annotations', () {
    final catalog = FoldboardWebMcpCatalog(
      invoke: (name, arguments) => {'ok': true},
    );
    final tools = {for (final tool in catalog.allTools) tool.name: tool};

    expect(tools['reveal-card']!.annotations?.readOnly, isFalse);
    expect(tools['fit-content']!.annotations?.readOnly, isFalse);
    expect(tools['get-user-context']!.annotations?.readOnly, isTrue);
    expect(tools['get-request']!.annotations?.readOnly, isTrue);
    expect(tools['resolve-request']!.annotations?.readOnly, isFalse);

    Map properties(String name) =>
        tools[name]!.inputSchema['properties'] as Map;
    expect(properties('apply-changes')['return']['default'], 'summary');
    expect(properties('apply-changes')['validate']['default'], isFalse);
    final changes = properties('apply-changes')['changes']['properties'] as Map;
    expect(changes.containsKey('version'), isFalse);
    expect(changes['revision']['minimum'], 0);
    expect(
      changes['edges']['items']['properties']['from']['description'],
      allOf(contains('Upstream'), contains('inner exit')),
    );
    expect(
      changes['edges']['items']['properties']['to']['description'],
      allOf(contains('Downstream'), contains('inner entry')),
    );
    expect(properties('create-project')['clientRequestId']['maxLength'], 128);
    expect(properties('get-area')['limit']['default'], 20);
    expect(properties('get-area')['limit']['maximum'], 100);
    expect(properties('get-area')['includeCoordinates']['default'], isFalse);
    expect(properties('get-area')['includeView']['default'], isFalse);
    expect(properties('get-changes')['mode']['default'], 'compact');
    expect(properties('search-architecture')['limit']['maximum'], 100);
    expect(
      tools['apply-changes']!.description,
      contains('Trace follows edges only'),
    );
    expect(
      tools['apply-changes']!.description,
      allOf(
        contains('target fold enters its inner chain'),
        contains('source fold continues from its inner exit'),
        contains('Nested folds resolve recursively'),
        contains('empty fold stays a step'),
      ),
    );
    expect(
      tools['validate-architecture']!.description,
      contains('Run it after writes'),
    );
    expect(tools['list-projects']!.description, contains('use it directly'));

    final encoded = jsonEncode([
      for (final tool in catalog.allTools)
        {
          'name': tool.name,
          'description': tool.description,
          'inputSchema': tool.inputSchema,
          'annotations': {
            'readOnlyHint': tool.annotations?.readOnly,
            'untrustedContentHint': tool.annotations?.untrustedContent,
          },
        },
    ]);
    expect(encoded.length, lessThan(17500));
  });

  test(
    'execution forwards input and honours cancellation before dispatch',
    () async {
      var calls = 0;
      final catalog = FoldboardWebMcpCatalog(
        invoke: (name, arguments) {
          calls++;
          return {'ok': true, 'tool': name, 'arguments': arguments};
        },
      );
      final tool = catalog.boardTools.first;

      final result = await Future<Object?>.value(
        tool.execute({
          'projectId': 'p1',
        }, WebMcpExecutionContext(isCancelled: () => false)),
      ) as Map;
      expect(result['tool'], tool.name);
      expect(result['arguments'], {'projectId': 'p1'});

      final cancelled = await Future<Object?>.value(
        tool.execute(const {}, WebMcpExecutionContext(isCancelled: () => true)),
      ) as Map;
      expect(cancelled['code'], 'cancelled');
      expect(calls, 1);
    },
  );

  test('package handlers retain project and revision guards', () async {
    final stores = ProjectStores();
    final vm = ProjectsViewModel(repository: stores.repository());
    addTearDown(() {
      vm.dispose();
      vm.repository.dispose();
    });
    final tools = {for (final tool in vm.webMcp.allTools) tool.name: tool};
    final context = WebMcpExecutionContext(isCancelled: () => false);

    await Future<Object?>.value(
      tools['open-project']!.execute({'id': Project.defaultId}, context),
    );
    final staleProject = await Future<Object?>.value(
      tools['get-outline']!.execute({'projectId': 'stale'}, context),
    ) as Map;
    expect(staleProject['code'], 'project-conflict');

    final revision = vm.planner!.repository.revision;
    vm.planner!.addNode(title: 'Human edit');
    final staleRevision = await Future<Object?>.value(
      tools['apply-changes']!.execute({
        'projectId': Project.defaultId,
        'expectedRevision': revision,
        'changes': const <String, Object?>{},
      }, context),
    ) as Map;
    expect(staleRevision['code'], 'revision-conflict');
  });

  testWidgets('scopes register and remove only currently serviceable tools', (
    tester,
  ) async {
    final catalog = FoldboardWebMcpCatalog(
      invoke: (name, arguments) => {'ok': true},
    );
    final active = <String>{};

    WebMcpRegistrationAttempt registrationStarter(
      WebMcpTool tool, {
      required List<String> exposedTo,
    }) {
      active.add(tool.name);
      return WebMcpRegistrationAttempt(
        ready: Future.value(
          WebMcpRegistration(tool.name, () => active.remove(tool.name)),
        ),
        cancel: () => active.remove(tool.name),
      );
    }

    Widget app({required bool board, required bool requests}) =>
        FoldboardWebMcpScopes(
          catalog: catalog,
          boardEnabled: board,
          requestsEnabled: requests,
          registrationStarter: registrationStarter,
          supportCheck: () => true,
          child: const SizedBox(),
        );

    await tester.pumpWidget(app(board: false, requests: false));
    await tester.pumpAndSettle();
    expect(active, catalog.projectTools.map((tool) => tool.name).toSet());

    await tester.pumpWidget(app(board: true, requests: false));
    await tester.pumpAndSettle();
    expect(active, hasLength(15));
    expect(active, isNot(contains('get-request')));

    await tester.pumpWidget(app(board: true, requests: true));
    await tester.pumpAndSettle();
    expect(active, hasLength(18));

    await tester.pumpWidget(app(board: false, requests: false));
    await tester.pumpAndSettle();
    expect(active, catalog.projectTools.map((tool) => tool.name).toSet());

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(active, isEmpty);
  });
}
