import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/models/app_settings.dart';
import 'board_store.dart';

enum SettingsFailure { read, write }

class SettingsRepository extends ChangeNotifier {
  SettingsRepository({required BoardStore store}) : _store = store {
    try {
      final raw = store.read();
      if (raw != null) {
        _value = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      failure = SettingsFailure.read;
      _loadFailed = true;
    }
  }
  final BoardStore _store;
  AppSettings _value = const AppSettings();
  AppSettings get value => _value;
  bool _loadFailed = false;
  bool get canEdit => !_loadFailed;
  SettingsFailure? failure;

  bool save(AppSettings next, {bool reset = false}) {
    if (_loadFailed && !reset) return false;
    try {
      _store.write(jsonEncode(next.toJson()));
      _value = next;
      failure = null;
      _loadFailed = false;
      notifyListeners();
      return true;
    } catch (_) {
      failure = SettingsFailure.write;
      notifyListeners();
      return false;
    }
  }
}
