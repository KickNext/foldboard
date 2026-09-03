import 'package:web/web.dart' as web;

import '../../webmcp/webmcp_bridge.dart';
import 'board_store.dart';

class BrowserBoardStore implements BoardStore, WriteGuardedStore {
  BrowserBoardStore({required this.key});
  final String key;
  @override
  String? read() => web.window.localStorage.getItem(key);
  @override
  void write(String json) {
    checkWrite();
    web.window.localStorage.setItem(key, json);
  }

  @override
  void checkWrite() {
    if (!WebMcpBridge.hasWriteLock) throw const StorageConflict();
  }
}
