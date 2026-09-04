import 'dart:convert';
import 'dart:io';

import 'package:foldboard/domain/models/project.dart';
import 'package:foldboard/storage_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every key derives from the one prefix', () {
    const p = StorageKeys.prefix;
    expect(StorageKeys.settings, '$p.settings');
    expect(StorageKeys.projects, '$p.projects');
    expect(StorageKeys.projectBoard('abc'), '$p.project.abc.board');
    expect(StorageKeys.projectRequests('abc'), '$p.project.abc.requests');
    expect(StorageKeys.editorLock, '$p-editor');
  });

  test('the first project is stored like any other', () {
    const first = Project(id: Project.defaultId, name: 'My project');
    expect(first.boardKey, StorageKeys.projectBoard(Project.defaultId));
    expect(first.requestsKey, StorageKeys.projectRequests(Project.defaultId));
    const other = Project(id: 'p1', name: 'Other');
    expect(other.boardKey, StorageKeys.projectBoard('p1'));
    expect(other.requestsKey, StorageKeys.projectRequests('p1'));
  });

  test('Dart browser service, tool catalogue and manifest share names', () {
    final browserService = File('lib/data/services/browser_platform_web.dart')
        .readAsStringSync();
    expect(browserService, contains('StorageKeys.editorLock'));
    final catalog = File('lib/webmcp/foldboard_webmcp.dart').readAsStringSync();
    expect(catalog, contains("'list-projects'"));
    expect(catalog, contains("'apply-changes'"));
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync()) as Map;
    expect(manifest['id'], StorageKeys.prefix);
  });

  test('no earlier app name survives in code, page or config', () {
    // 'archy' only as a whole word: 'hierarchy' is fine.
    final earlierNames = [RegExp('coboard'), RegExp(r'\barchy\b')];
    final sources = [
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('generated')),
      File('web/index.html'),
      File('web/manifest.json'),
      File('pubspec.yaml'),
    ];
    for (final file in sources) {
      final text = file.readAsStringSync().toLowerCase();
      for (final name in earlierNames) {
        expect(
          name.hasMatch(text),
          isFalse,
          reason: '${file.path} names ${name.pattern}',
        );
      }
    }
  });
}
