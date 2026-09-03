import 'package:foldboard/data/repositories/architecture_repository.dart';
import 'package:foldboard/data/repositories/board_store.dart';
import 'package:foldboard/l10n/l10n.dart';
import 'package:foldboard/main.dart';
import 'package:foldboard/ui/features/planner/view_models/planner_view_model.dart';
import 'package:foldboard/ui/features/planner/views/planner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class UnavailableStore implements BoardStore {
  UnavailableStore({this.failRead = false});
  final bool failRead;
  @override
  String? read() {
    if (failRead) throw StateError('Storage blocked');
    return null;
  }

  @override
  void write(String json) => throw StateError('Storage full');
}

void main() {
  testWidgets('en-US overrides the device locale, including Material strings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.binding.platformDispatcher.localeTestValue = const Locale(
      'ru',
      'RU',
    );
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
    final vm = PlannerViewModel(repository: ArchitectureRepository());
    addTearDown(vm.dispose);
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PlannerPage));
    expect(Localizations.localeOf(context), defaultAppLocale);
    expect(context.l10n.localeName, 'en_US');
    expect(MaterialLocalizations.of(context).copyButtonLabel, 'Copy');
    expect(find.text('This level is empty'), findsOneWidget);
    expect(find.byKey(const Key('empty-add-block')), findsOneWidget);
    expect(find.byTooltip('Find on board'), findsOneWidget);
    expect(find.byTooltip('Export project'), findsOneWidget);
    expect(find.byTooltip('Add fold'), findsOneWidget);
    await tester.tap(find.byKey(const Key('add-block')));
    await tester.pumpAndSettle();
    expect(vm.nodes.single.title, isEmpty);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Linked data'), findsNothing);
    expect(find.text('Draw arrow'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('locale changes never translate or overwrite board content', (
    tester,
  ) async {
    final vm = PlannerViewModel(repository: ArchitectureRepository());
    addTearDown(vm.dispose);
    vm.addNode(title: 'Editor');
    vm.updateSelected(description: 'User-entered text');
    final before = vm.prettyJson;
    await tester.pumpWidget(FoldboardApp(viewModel: vm));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-details')));
    await tester.pumpAndSettle();
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('User-entered text'), findsWidgets);
    await tester.pumpWidget(
      FoldboardApp(viewModel: vm, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(vm.prettyJson, before);
    expect(tester.takeException(), isNull);
  });

  for (final failRead in [true, false]) {
    testWidgets(
      'storage ${failRead ? 'read' : 'write'} failures use localized UI messages',
      (tester) async {
        final repo = ArchitectureRepository(
          store: UnavailableStore(failRead: failRead),
        );
        final vm = PlannerViewModel(repository: repo);
        addTearDown(() {
          vm.dispose();
          repo.dispose();
        });
        await tester.pumpWidget(FoldboardApp(viewModel: vm));
        await tester.pumpAndSettle();
        if (!failRead) {
          vm.addNode();
          repo.flush();
          await tester.pumpAndSettle();
        }
        final strings = tester.element(find.byType(PlannerPage)).l10n;
        expect(
          find.text(
            failRead ? strings.storageReadFailed : strings.storageWriteFailed,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('StateError'), findsNothing);
      },
    );
  }

  testWidgets(
    'delete confirmation uses a localized placeholder and preserves content on cancel',
    (tester) async {
      final vm = PlannerViewModel(repository: ArchitectureRepository());
      addTearDown(vm.dispose);
      vm.addNode(title: 'Editor');
      await tester.pumpWidget(FoldboardApp(viewModel: vm));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-details')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-inspector')));
      await tester.pumpAndSettle();
      expect(find.text('Delete “Editor”?'), findsOneWidget);
      expect(
        find.text('Connected arrows will also be deleted.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(vm.nodes.single.title, 'Editor');
    },
  );
}
