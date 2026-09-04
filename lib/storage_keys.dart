/// Every name the app owns in the browser, defined once.
///
/// localStorage keys, the Web Lock that grants one tab write access and the
/// browser services all derive from [prefix]. WebMCP tool registration and
/// browser integration are both owned by Dart.
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
}
