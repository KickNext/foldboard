import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'storage_keys.dart';
import 'webmcp/webmcp_bridge.dart';

import 'l10n/l10n.dart';

import 'data/repositories/projects_repository.dart';
import 'data/repositories/browser_board_store.dart';
import 'ui/core/app_theme.dart';
import 'ui/core/write_access_scope.dart';
import 'ui/features/planner/view_models/planner_view_model.dart';
import 'ui/features/planner/views/planner_page.dart';
import 'ui/features/projects/view_models/projects_view_model.dart';
import 'ui/features/projects/views/projects_page.dart';
import 'data/repositories/settings_repository.dart';
import 'ui/features/settings/view_models/settings_view_model.dart';

bool shouldOpenExample(Uri uri) => uri.queryParameters['demo'] == '1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final writeAccess = await WebMcpBridge.writeReady;
  final settings = SettingsViewModel(
    repository: SettingsRepository(
      store: BrowserBoardStore(key: StorageKeys.settings),
    ),
  );
  final repository = ProjectsRepository(
    readOnly: !writeAccess,
    catalog: BrowserBoardStore(key: StorageKeys.projects),
    boardStore: (key) => BrowserBoardStore(key: key),
    initialName: lookupAppLocalizations(defaultAppLocale).myProject,
  );
  final projects = ProjectsViewModel(repository: repository)
    ..agentCanWrite = (() => !settings.value.agentReadOnly);
  if (shouldOpenExample(Uri.base)) projects.openExample();
  runApp(
    FoldboardApp(
      writeAccess: writeAccess,
      projects: projects,
      settings: settings,
    ),
  );
}

class FoldboardApp extends StatelessWidget {
  const FoldboardApp({
    super.key,
    this.viewModel,
    this.projects,
    this.settings,
    this.locale = defaultAppLocale,
    this.writeAccess = true,
  }) : assert((viewModel == null) != (projects == null));
  final PlannerViewModel? viewModel;
  final ProjectsViewModel? projects;
  final SettingsViewModel? settings;
  final Locale locale;
  final bool writeAccess;

  @override
  Widget build(BuildContext context) => settings == null
      ? _app()
      : ListenableBuilder(
          listenable: settings!,
          builder: (_, _) => SettingsScope(viewModel: settings!, child: _app()),
        );

  Widget _app() => MaterialApp(
    title: 'Foldboard',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: settings?.themeMode ?? ThemeMode.dark,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) {
      // Flutter web writes its own theme-color meta after the static ones in
      // index.html, so the browser chrome follows the palette only if the app
      // states it. Address bar and PWA splash match the board this way.
      final palette = Theme.of(context).extension<AppPalette>()!;
      SystemChrome.setSystemUIOverlayStyle(
        SystemUiOverlayStyle(
          statusBarColor: palette.background,
          systemNavigationBarColor: palette.background,
        ),
      );
      viewModel?.strings = context.l10n;
      projects?.strings = context.l10n;
      projects?.planner?.strings = context.l10n;
      if (settings != null) {
        projects?.agentCanWrite = (() => !settings!.value.agentReadOnly);
        viewModel?.agentCanWrite = (() => !settings!.value.agentReadOnly);
      }
      return WriteAccessScope(canWrite: writeAccess, child: child!);
    },
    home: projects != null
        ? ProjectsPage(viewModel: projects!)
        : PlannerPage(viewModel: viewModel!),
  );
}
