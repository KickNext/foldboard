import 'dart:convert';

/// A human-authored request. Context is captured once; it does not follow later
/// selection or navigation. The private JSON keeps nested context immutable.
class BoardRequest {
  BoardRequest({
    required this.id,
    required this.text,
    required Map<String, dynamic> context,
    required this.createdAt,
    this.version = 1,
    this.status = 'pending',
    this.response,
    this.handledAt,
  }) : _context = jsonEncode(context);
  final String id;
  final String text;
  final String _context;
  final DateTime createdAt;
  final int version;
  final String status;
  final String? response;
  final DateTime? handledAt;
  Map<String, dynamic> get context =>
      jsonDecode(_context) as Map<String, dynamic>;
  List<Map<String, dynamic>> get targets =>
      (context['targets'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'context': context,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'version': version,
    'status': status,
    if (response != null) 'response': response,
    if (handledAt != null) 'handledAt': handledAt!.toUtc().toIso8601String(),
  };
  factory BoardRequest.fromJson(Map<String, dynamic> json) {
    final value = BoardRequest(
      id: json['id'] as String,
      text: json['text'] as String,
      context: Map<String, dynamic>.from(json['context'] as Map),
      createdAt: DateTime.parse(json['createdAt'] as String),
      version: json['version'] as int,
      status: json['status'] as String,
      response: json['response'] as String?,
      handledAt: json['handledAt'] == null
          ? null
          : DateTime.parse(json['handledAt'] as String),
    );
    if (value.id.isEmpty ||
        value.text.trim().isEmpty ||
        value.text.length > 4000 ||
        value.version < 1 ||
        !['pending', 'handled'].contains(value.status) ||
        (value.response?.length ?? 0) > 4000) {
      throw const FormatException('Invalid board request');
    }
    for (final target in value.targets) {
      if (target['id'] is! String ||
          target['title'] is! String ||
          target['type'] is! String) {
        throw const FormatException('Invalid request target');
      }
    }
    if (value.context['levelTitle'] is! String ||
        value.context['boardRevision'] is! int) {
      throw const FormatException('Invalid request context');
    }
    return value;
  }
  BoardRequest handled(String? response) => BoardRequest(
    id: id,
    text: text,
    context: context,
    createdAt: createdAt,
    version: version + 1,
    status: 'handled',
    response: response,
    handledAt: DateTime.now().toUtc(),
  );
  BoardRequest reopen() => BoardRequest(
    id: id,
    text: text,
    context: context,
    createdAt: createdAt,
    version: version + 1,
  );
}
