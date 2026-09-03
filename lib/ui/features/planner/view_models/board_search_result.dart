enum BoardSearchKind { block, process }

class BoardSearchResult {
  const BoardSearchResult({
    required this.id,
    required this.title,
    required this.kind,
    required this.path,
    required this.description,
  });
  final String id;
  final String title;
  final BoardSearchKind kind;
  final String path;
  final String description;
}
