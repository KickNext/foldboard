import 'package:foldboard/data/repositories/board_store.dart';
import 'package:foldboard/data/repositories/projects_repository.dart';

class MemoryProjectStore implements BoardStore {
  String? value;
  bool failWrite = false;
  @override
  String? read() => value;
  @override
  void write(String json) {
    if (failWrite) throw StateError('Storage full');
    value = json;
  }
}

class ProjectStores {
  final catalog = MemoryProjectStore();
  final boards = <String, MemoryProjectStore>{};

  /// Make every board key opened from now on reject writes.
  bool failNewBoards = false;

  MemoryProjectStore board(String key) => boards.putIfAbsent(
    key,
    () => MemoryProjectStore()..failWrite = failNewBoards,
  );
  ProjectsRepository repository() => ProjectsRepository(
    catalog: catalog,
    boardStore: board,
    initialName: 'My project',
  );
}
