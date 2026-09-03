abstract final class WebMcpBridge {
  static Future<bool> get writeReady async => true;
  static bool get hasWriteLock => true;
  static Future<String?> pickJson() async => null;
  static void initialize(
    String Function(String) handler,
    void Function() flush,
  ) {}
  static void download(
    String filename,
    String content, {
    String type = 'application/json',
  }) {}
  static void downloadBytes(String filename, String type, List<int> bytes) {}
  static McpStatus get status => (available: false, registered: 0, total: 0);
}

typedef McpStatus = ({bool available, int registered, int total});
