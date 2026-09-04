import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../storage_keys.dart';

/// Browser-only services kept outside the app's state and domain layers.
abstract final class BrowserPlatform {
  static const _lockRetryDelays = <Duration>[
    Duration.zero,
    Duration(milliseconds: 25),
    Duration(milliseconds: 50),
    Duration(milliseconds: 100),
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 800),
  ];
  static const _maxJsonBytes = 10 * 1024 * 1024;

  static bool _hasWriteLock = false;
  static void Function()? _flush;
  static final Future<bool> _writeReady = _acquireWriteLock();
  static final bool _lifecycleListenersInstalled = _installLifecycleListeners();

  static Future<bool> get writeReady => _writeReady;

  /// The lock is held for this page's lifetime and intentionally not handed
  /// over while the page remains open.
  static bool get hasWriteLock => _hasWriteLock;

  static void setFlush(void Function()? flush) {
    _lifecycleListenersInstalled;
    _flush = flush;
  }

  static Future<String?> pickJson() {
    final result = Completer<String?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = '.json,application/json';

    void complete(String? value) {
      if (!result.isCompleted) result.complete(value);
    }

    input.addEventListener(
      'cancel',
      ((web.Event _) => complete(null)).toJS,
      web.AddEventListenerOptions(once: true),
    );
    input.addEventListener(
      'change',
      ((web.Event _) => unawaited(_readSelectedJson(input, result))).toJS,
      web.AddEventListenerOptions(once: true),
    );
    input.click();
    return result.future;
  }

  static Future<void> _readSelectedJson(
    web.HTMLInputElement input,
    Completer<String?> result,
  ) async {
    final files = input.files;
    final file = files == null || files.length == 0 ? null : files.item(0);
    if (file == null) {
      if (!result.isCompleted) result.complete(null);
      return;
    }
    if (file.size > _maxJsonBytes) {
      if (!result.isCompleted) {
        result.completeError(StateError('File exceeds 10 MB'));
      }
      return;
    }
    try {
      final content = (await file.text().toDart).toDart;
      if (!result.isCompleted) result.complete(content);
    } catch (error, stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }
  }

  static void download(
    String filename,
    String content, {
    String type = 'application/json',
  }) => _save(
    filename,
    web.Blob(
      <web.BlobPart>[content.toJS].toJS,
      web.BlobPropertyBag(type: type),
    ),
  );

  static void downloadBytes(String filename, String type, List<int> bytes) =>
      _save(
        filename,
        web.Blob(
          <web.BlobPart>[Uint8List.fromList(bytes).toJS].toJS,
          web.BlobPropertyBag(type: type),
        ),
      );

  static void _save(String filename, web.Blob blob) {
    final url = web.URL.createObjectURL(blob);
    web.HTMLAnchorElement()
      ..href = url
      ..download = filename
      ..click();
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(url));
  }

  static Future<bool> _acquireWriteLock() async {
    if (!(web.window.navigator as JSObject).has('locks')) return false;
    for (final delay in _lockRetryDelays) {
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (await _tryWriteLock()) return true;
    }
    return false;
  }

  static Future<bool> _tryWriteLock() {
    final result = Completer<bool>();

    JSAny? onGranted(web.Lock? lock) {
      final granted = lock != null;
      _hasWriteLock = granted;
      if (!result.isCompleted) result.complete(granted);
      // A pending promise keeps the exclusive lock for the document lifetime.
      return granted ? Completer<JSAny?>().future.toJS : null;
    }

    final request = web.window.navigator.locks.request(
      StorageKeys.editorLock,
      web.LockOptions(ifAvailable: true),
      onGranted.toJS,
    );
    unawaited(
      request.toDart.catchError((Object _) {
        if (!result.isCompleted) result.complete(false);
        return null;
      }),
    );
    return result.future;
  }

  static bool _installLifecycleListeners() {
    void flush(web.Event _) => _flush?.call();
    web.window.addEventListener('pagehide', flush.toJS);
    web.window.addEventListener('beforeunload', flush.toJS);
    return true;
  }
}
