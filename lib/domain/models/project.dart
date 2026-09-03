import '../../storage_keys.dart';

class Project {
  const Project({required this.id, required this.name});

  /// The project created on first start, before a catalogue exists. It is
  /// stored like any other project.
  static const defaultId = 'main';
  final String id;
  final String name;
  String get requestsKey => StorageKeys.projectRequests(id);
  String get boardKey => StorageKeys.projectBoard(id);
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
