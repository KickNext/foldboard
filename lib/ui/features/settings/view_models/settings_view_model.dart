import 'package:flutter/material.dart';

import '../../../../data/repositories/settings_repository.dart';
import '../../../../domain/models/app_settings.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({required this.repository}) {
    repository.addListener(_changed);
  }
  final SettingsRepository repository;
  int feedbackVersion = 0;
  void _changed() {
    feedbackVersion++;
    notifyListeners();
  }

  AppSettings get value => repository.value;
  bool get canEdit => repository.canEdit;
  bool get showGrid => value.showGrid;
  SettingsFailure? get failure => repository.failure;
  ThemeMode get themeMode => switch (value.appearance) {
    Appearance.dark => ThemeMode.dark,
    Appearance.light => ThemeMode.light,
    Appearance.system => ThemeMode.system,
  };
  void setAppearance(Appearance appearance) =>
      repository.save(value.copyWith(appearance: appearance));
  void setShowGrid(bool showGrid) =>
      repository.save(value.copyWith(showGrid: showGrid));
  void setAgentReadOnly(bool value) =>
      repository.save(this.value.copyWith(agentReadOnly: value));
  void reset() => repository.save(const AppSettings(), reset: true);
  @override
  void dispose() {
    repository.removeListener(_changed);
    super.dispose();
  }
}

class SettingsScope extends InheritedNotifier<SettingsViewModel> {
  const SettingsScope({
    super.key,
    required SettingsViewModel viewModel,
    required super.child,
  }) : super(notifier: viewModel);
  static SettingsViewModel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.notifier;
}
