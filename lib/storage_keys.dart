/// Every name the app owns in the browser, defined once.
///
/// localStorage keys, the Web Lock that grants one tab write access and the
/// global namespace `web/webmcp.js` exposes to Dart all derive from [prefix].
/// `webmcp.js` runs before Dart and repeats the namespace and the lock name as
/// literals; `test/storage_keys_test.dart` fails if the two sides drift.
abstract final class StorageKeys {
  static const prefix = 'foldboard';

  /// Appearance, grid and agent read-only preferences.
  static const settings = '$prefix.settings';

  /// The project catalogue: ids, names and the active project.
  static const projects = '$prefix.projects';

  static String projectBoard(String id) => '$prefix.project.$id.board';
  static String projectRequests(String id) => '$prefix.project.$id.requests';

  /// Web Lock held by the one tab allowed to write.
  static const editorLock = '$prefix-editor';

  /// `window.<jsNamespace>` in webmcp.js: the bridge Dart calls into.
  static const jsNamespace = prefix;
}
