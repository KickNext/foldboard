/// Deterministic graph structure shared by ranking and component packing.
class LayoutGraph {
  LayoutGraph(Iterable<String> ids, Iterable<(String, String)> edges)
    : ids = ids.toList()..sort() {
    for (final id in this.ids) {
      outgoing[id] = <String>[];
      incoming[id] = <String>[];
    }
    final unique = edges.toSet().toList()
      ..sort((a, b) {
        final from = a.$1.compareTo(b.$1);
        return from == 0 ? a.$2.compareTo(b.$2) : from;
      });
    for (final (from, to) in unique) {
      if (from == to ||
          !outgoing.containsKey(from) ||
          !outgoing.containsKey(to)) {
        continue;
      }
      outgoing[from]!.add(to);
      incoming[to]!.add(from);
    }
  }

  final List<String> ids;
  final outgoing = <String, List<String>>{};
  final incoming = <String, List<String>>{};

  List<List<String>> components() {
    final seen = <String>{};
    final result = <List<String>>[];
    for (final root in ids) {
      if (!seen.add(root)) continue;
      final queue = [root];
      for (var i = 0; i < queue.length; i++) {
        for (final next in [...outgoing[queue[i]]!, ...incoming[queue[i]]!]) {
          if (seen.add(next)) queue.add(next);
        }
      }
      result.add(queue..sort());
    }
    return result;
  }

  /// Iterative Kosaraju: long chains do not consume the Dart call stack.
  List<List<String>> stronglyConnected() {
    final seen = <String>{};
    final finish = <String>[];
    for (final root in ids) {
      if (!seen.add(root)) continue;
      final stack = <(String, int)>[(root, 0)];
      while (stack.isNotEmpty) {
        final (id, index) = stack.removeLast();
        if (index == outgoing[id]!.length) {
          finish.add(id);
          continue;
        }
        stack.add((id, index + 1));
        final next = outgoing[id]![index];
        if (seen.add(next)) stack.add((next, 0));
      }
    }
    seen.clear();
    final result = <List<String>>[];
    for (final root in finish.reversed) {
      if (!seen.add(root)) continue;
      final component = [root];
      for (var i = 0; i < component.length; i++) {
        for (final next in incoming[component[i]]!) {
          if (seen.add(next)) component.add(next);
        }
      }
      result.add(component..sort());
    }
    return result;
  }

  /// Keep inter-component edges. Inside each cycle, prefer actual entry points,
  /// then follow the flow. Only edges against this stable order become feedback.
  Map<String, List<String>> rankingDag() {
    final componentOf = <String, int>{};
    final order = <String, int>{};
    final components = stronglyConnected();
    for (var i = 0; i < components.length; i++) {
      for (final id in components[i]) {
        componentOf[id] = i;
      }
    }
    for (var i = 0; i < components.length; i++) {
      final members = components[i];
      final roots = [...members]
        ..sort((a, b) {
          final aEntries = incoming[a]!
              .where((n) => componentOf[n] != i)
              .length;
          final bEntries = incoming[b]!
              .where((n) => componentOf[n] != i)
              .length;
          final entry = bEntries.compareTo(aEntries);
          return entry == 0 ? a.compareTo(b) : entry;
        });
      var index = 0;
      for (final root in roots) {
        final stack = [root];
        while (stack.isNotEmpty) {
          final id = stack.removeLast();
          if (order.containsKey(id)) continue;
          order[id] = index++;
          for (final next in outgoing[id]!.reversed) {
            if (componentOf[next] == i && !order.containsKey(next)) {
              stack.add(next);
            }
          }
        }
      }
    }
    return {
      for (final id in ids)
        id: [
          for (final next in outgoing[id]!)
            if (componentOf[id] != componentOf[next] ||
                order[id]! < order[next]!)
              next,
        ],
    };
  }
}
