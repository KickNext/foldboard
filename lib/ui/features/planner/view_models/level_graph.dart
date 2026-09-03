import 'dart:ui';

import '../../../../domain/models/architecture_models.dart';

enum ReferenceFlow { input, output, both, outside }

/// A presentation of one level. Reference cards and summarized arrows are
/// never written into the document; their IDs point to the original objects.
class LevelGraph {
  const LevelGraph(
    this.nodes,
    this.edges,
    this.processIds,
    this.referenceIds,
    this.edgeSources,
    this.referenceSources,
    this.referenceFlows,
  );
  final List<ArchitectureNode> nodes;
  final List<ArchitectureEdge> edges;
  final Set<String> processIds;
  final Set<String> referenceIds;
  final Map<String, List<String>> edgeSources;
  final Map<String, List<String>> referenceSources;
  final Map<String, ReferenceFlow> referenceFlows;

  factory LevelGraph.build({
    required String? levelId,
    required List<ArchitectureNode> nodes,
    required List<ArchitectureGroup> groups,
    required List<ArchitectureEdge> edges,
    Map<String, Offset> referencePositions = const {},
    String? connectionFrom,
  }) {
    final all = {
      for (final n in nodes) n.id: n,
      for (final g in groups)
        g.id: ArchitectureNode(
          id: g.id,
          title: g.title,
          description: g.description,
          position: g.position,
          parentId: g.parentId,
        ),
    };
    final processIds = groups.map((g) => g.id).toSet();
    final visible = {
      for (final n in all.values.where((n) => n.parentId == levelId)) n.id: n,
    };
    String? representative(String id) {
      if (id == levelId) return id;
      var object = all[id];
      while (object != null) {
        if (object.parentId == levelId) return object.id;
        object = all[object.parentId];
      }
      return null;
    }

    final references = <String>{};
    final pairs = <(String, String), List<String>>{};
    final incomingReferences = <String>{};
    final boundaryInputs = <String>{};
    final boundaryOutputs = <String>{};
    final referenceSources = <String, List<String>>{};
    for (final edge in edges) {
      // The current process is the level boundary, not a card inside itself.
      // A direct process connection exposes only its external endpoint as an
      // input/output reference. Its source edge stays available for deletion.
      if (levelId != null && (edge.from == levelId || edge.to == levelId)) {
        final input = edge.to == levelId;
        final externalId = input ? edge.from : edge.to;
        final external = representative(externalId) ?? externalId;
        if (!visible.containsKey(external) && all.containsKey(external)) {
          references.add(external);
          (referenceSources[external] ??= []).add(edge.id);
          if (input) {
            incomingReferences.add(external);
            boundaryInputs.add(external);
          } else {
            boundaryOutputs.add(external);
          }
        }
        continue;
      }
      final from = representative(edge.from);
      final to = representative(edge.to);
      if ((from == null && to == null) || (from != null && from == to)) {
        continue;
      }
      final source = from ?? edge.from;
      final target = to ?? edge.to;
      if (!visible.containsKey(source)) {
        references.add(source);
        incomingReferences.add(source);
      }
      if (!visible.containsKey(target)) references.add(target);
      (pairs[(source, target)] ??= []).add(edge.id);
    }
    if (connectionFrom != null &&
        !visible.containsKey(connectionFrom) &&
        all.containsKey(connectionFrom)) {
      references.add(connectionFrom);
      incomingReferences.add(connectionFrom);
    }
    final bounds = visible.isEmpty
        ? const Rect.fromLTWH(400, 300, 260, 118)
        : visible.values
              .map((n) => n.position & const Size(260, 118))
              .reduce((a, b) => a.expandToInclude(b));
    final inputs = <String>{};
    final outputs = <String>{};
    for (final (from, to) in pairs.keys) {
      if (references.contains(from) && !references.contains(to)) {
        inputs.add(from);
      }
      if (references.contains(to) && !references.contains(from)) {
        outputs.add(to);
      }
    }
    inputs.addAll(boundaryInputs);
    outputs.addAll(boundaryOutputs);
    var leftRow = 0;
    var rightRow = 0;
    for (final id in references) {
      final n = all[id];
      if (n == null) continue;
      final left = incomingReferences.contains(id);
      final row = left ? leftRow++ : rightRow++;
      visible[id] = n.copyWith(
        position:
            referencePositions[id] ??
            Offset(
              left ? bounds.left - 440 : bounds.right + 180,
              bounds.top + row * 182,
            ),
      );
    }
    return LevelGraph(
      List.unmodifiable(visible.values),
      List.unmodifiable([
        for (final entry in pairs.entries)
          ArchitectureEdge(
            id: entry.value.first,
            from: entry.key.$1,
            to: entry.key.$2,
          ),
      ]),
      Set.unmodifiable(processIds),
      Set.unmodifiable(references),
      Map.unmodifiable({
        for (final ids in pairs.values)
          ids.first: List<String>.unmodifiable(ids),
      }),
      Map.unmodifiable({
        for (final entry in referenceSources.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
      Map.unmodifiable({
        for (final id in references)
          id: inputs.contains(id)
              ? (outputs.contains(id)
                    ? ReferenceFlow.both
                    : ReferenceFlow.input)
              : (outputs.contains(id)
                    ? ReferenceFlow.output
                    : ReferenceFlow.outside),
      }),
    );
  }
}
