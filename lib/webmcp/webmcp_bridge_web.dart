/// The page side of this bridge is `web/webmcp.js`, which puts everything
/// under `window.foldboard` (StorageKeys.jsNamespace).
@JS('foldboard')
library;

import 'dart:convert';
import 'dart:js_interop';

@JS('setHandler')
external void _setHandler(JSFunction handler, JSFunction flush);

@JS('download')
external void _download(JSString filename, JSString content, JSString type);

@JS('downloadBytes')
external void _downloadBytes(JSString filename, JSString type, JSString base64);

@JS('mcpStatus')
external JSString _mcpStatus();

@JS('writeReady')
external JSPromise<JSBoolean> get _writeReady;

@JS('hasWriteLock')
external bool get _hasWriteLock;

@JS('pickJson')
external JSPromise<JSAny?> _pickJson();

abstract final class WebMcpBridge {
  static Future<bool> get writeReady async => (await _writeReady.toDart).toDart;

  /// Whether this tab holds the editor lock. Read on every write: the lock is
  /// granted once per page lifetime and never handed over.
  static bool get hasWriteLock => _hasWriteLock;
  static Future<String?> pickJson() async =>
      (await _pickJson().toDart)?.dartify() as String?;
  static void initialize(
    String Function(String) handler,
    void Function() flush,
  ) {
    _setHandler(((JSString raw) => handler(raw.toDart).toJS).toJS, flush.toJS);
  }

  static void download(
    String filename,
    String content, {
    String type = 'application/json',
  }) => _download(filename.toJS, content.toJS, type.toJS);

  static void downloadBytes(String filename, String type, List<int> bytes) =>
      _downloadBytes(filename.toJS, type.toJS, base64Encode(bytes).toJS);

  static McpStatus get status {
    final json = jsonDecode(_mcpStatus().toDart) as Map<String, dynamic>;
    return (
      available: json['available'] as bool,
      registered: (json['registered'] as num).toInt(),
      total: (json['total'] as num).toInt(),
    );
  }
}

typedef McpStatus = ({bool available, int registered, int total});
