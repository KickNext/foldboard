import 'dart:ui';

String textValue(
  Map<String, dynamic> json,
  String key, [
  String fallback = '',
]) => json[key] == null ? fallback : json[key] as String;

double numberValue(Map<String, dynamic> json, String key, double fallback) {
  final value = (json[key] as num?)?.toDouble() ?? fallback;
  if (!value.isFinite) throw FormatException('$key must be finite');
  return value;
}

class ArchitectureNode {
  const ArchitectureNode({
    required this.id,
    required this.title,
    this.description = '',
    this.position = Offset.zero,
    this.parentId,
  });
  final String id;
  final String title;
  final String description;
  final Offset position;
  final String? parentId;
  factory ArchitectureNode.fromJson(Map<String, dynamic> json) =>
      ArchitectureNode(
        id: textValue(json, 'id'),
        title: textValue(json, 'title', 'New block'),
        description: textValue(json, 'description'),
        position: Offset(
          numberValue(json, 'x', 400),
          numberValue(json, 'y', 300),
        ),
        parentId: json['parentId'] as String?,
      );
  ArchitectureNode copyWith({
    String? title,
    String? description,
    Offset? position,
    String? parentId,
    bool clearParent = false,
  }) => ArchitectureNode(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    position: position ?? this.position,
    parentId: clearParent ? null : parentId ?? this.parentId,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'x': position.dx,
    'y': position.dy,
    'parentId': parentId,
  };
}

class ArchitectureGroup {
  const ArchitectureGroup({
    required this.id,
    required this.title,
    this.description = '',
    this.position = Offset.zero,
    this.size = const Size(760, 480),
    this.parentId,
  });
  final String id;
  final String title;
  final String description;
  final Offset position;
  final Size size;
  final String? parentId;
  factory ArchitectureGroup.fromJson(Map<String, dynamic> json) =>
      ArchitectureGroup(
        id: textValue(json, 'id'),
        title: textValue(json, 'title', 'New area'),
        description: textValue(json, 'description'),
        parentId: json['parentId'] as String?,
        position: Offset(
          numberValue(json, 'x', 320),
          numberValue(json, 'y', 220),
        ),
        size: Size(
          numberValue(json, 'width', 760),
          numberValue(json, 'height', 480),
        ),
      );
  ArchitectureGroup copyWith({
    String? title,
    String? description,
    Offset? position,
    Size? size,
    String? parentId,
    bool clearParent = false,
  }) => ArchitectureGroup(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    position: position ?? this.position,
    size: size ?? this.size,
    parentId: clearParent ? null : parentId ?? this.parentId,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'x': position.dx,
    'y': position.dy,
    'width': size.width,
    'height': size.height,
    'parentId': parentId,
  };
}

class ArchitectureEdge {
  const ArchitectureEdge({
    required this.id,
    required this.from,
    required this.to,
  });
  final String id;
  final String from;
  final String to;
  factory ArchitectureEdge.fromJson(Map<String, dynamic> json) =>
      ArchitectureEdge(
        id: textValue(json, 'id'),
        from: textValue(json, 'from'),
        to: textValue(json, 'to'),
      );
  Map<String, dynamic> toJson() => {'id': id, 'from': from, 'to': to};
}
