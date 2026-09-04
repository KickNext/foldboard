/// Platform operations that only have meaningful implementations in a browser.
abstract final class BrowserPlatform {
  static Future<bool> get writeReady async => true;
  static bool get hasWriteLock => true;
  static Future<String?> pickJson() async => null;
  static void setFlush(void Function()? flush) {}
  static void download(
    String filename,
    String content, {
    String type = 'application/json',
  }) {}
  static void downloadBytes(String filename, String type, List<int> bytes) {}
}
