/// Build identity shown in Settings → About.
///
/// [appVersion] duplicates the `version:` field of `pubspec.yaml` because a
/// Flutter web build has no runtime access to the manifest without an extra
/// dependency. `test/app_info_test.dart` fails if the two drift apart.
abstract final class AppInfo {
  static const name = 'Foldboard';
  static const appVersion = '1.0.0';

  /// The WebMCP draft the bridge in `web/webmcp.js` implements.
  static const webMcpSpecUrl = 'https://webmachinelearning.github.io/webmcp/';
}
