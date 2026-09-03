abstract interface class BoardStore {
  String? read();
  void write(String json);
}

class StorageConflict implements Exception {
  const StorageConflict();
}

abstract interface class WriteGuardedStore {
  void checkWrite();
}

/// Detect stale sessions even outside the browser (imports, tests, other hosts).
/// Browser writers additionally hold an origin-wide Web Lock.
class CheckedBoardStore implements BoardStore {
  CheckedBoardStore(this.delegate);
  final BoardStore delegate;
  String? _baseline;
  bool _read = false;
  @override
  String? read() {
    _baseline = delegate.read();
    _read = true;
    return _baseline;
  }

  @override
  void write(String json) {
    checkWrite();
    delegate.write(json);
    _baseline = json;
  }

  void checkWrite() {
    if (delegate case final WriteGuardedStore guarded) guarded.checkWrite();
    if (!_read || delegate.read() != _baseline) throw const StorageConflict();
  }
}
