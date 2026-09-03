import 'board_store.dart';

class BrowserBoardStore implements BoardStore {
  BrowserBoardStore({required this.key});
  final String key;
  String? _json;
  @override
  String? read() => _json;
  @override
  void write(String json) => _json = json;
}
