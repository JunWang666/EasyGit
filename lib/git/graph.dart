import 'models.dart';

enum GraphPart {
  /// From the top edge of the row to the bottom edge.
  full,

  /// From the top edge to the commit node row center.
  top,

  /// From the row center to the bottom edge.
  bottom,
}

class GraphLine {
  const GraphLine(this.from, this.to, this.part, this.color);

  final int from;
  final int to;
  final GraphPart part;
  final int color;
}

/// What to draw for one commit row in the log.
class GraphRow {
  const GraphRow(this.lane, this.color, this.lines, this.width);

  final int lane;
  final int color;
  final List<GraphLine> lines;

  /// Number of lanes this row occupies.
  final int width;
}

/// Lays out the commit graph. [commits] must be in topological order
/// (children before parents), as produced by `git log --topo-order`.
List<GraphRow> buildGraph(List<CommitInfo> commits) {
  final lanes = <String?>[];
  final colors = <int>[];
  var nextColor = 0;
  final rows = <GraphRow>[];

  int freeSlot() {
    final i = lanes.indexOf(null);
    if (i >= 0) return i;
    lanes.add(null);
    colors.add(0);
    return lanes.length - 1;
  }

  for (final commit in commits) {
    final lines = <GraphLine>[];
    var lane = lanes.indexOf(commit.hash);
    final hasChild = lane >= 0;
    if (!hasChild) {
      lane = freeSlot();
      colors[lane] = nextColor++;
    }
    final color = colors[lane];
    if (hasChild) lines.add(GraphLine(lane, lane, GraphPart.top, color));

    // Other lanes either converge into this commit or pass through.
    for (var k = 0; k < lanes.length; k++) {
      if (k == lane) continue;
      final hash = lanes[k];
      if (hash == null) continue;
      if (hash == commit.hash) {
        lines.add(GraphLine(k, lane, GraphPart.top, colors[k]));
        lanes[k] = null;
      } else {
        lines.add(GraphLine(k, k, GraphPart.full, colors[k]));
      }
    }

    if (commit.parents.isEmpty) {
      lanes[lane] = null;
    } else {
      final first = commit.parents.first;
      final existing = lanes.indexOf(first);
      if (existing >= 0 && existing < lane) {
        // Join the lane on the left that already leads to the parent.
        lanes[lane] = null;
        lines.add(GraphLine(lane, existing, GraphPart.bottom, colors[existing]));
      } else if (existing > lane) {
        // Pull the lane on the right into this one so history stays left.
        lanes[lane] = first;
        lanes[existing] = null;
        lines.removeWhere((l) => l.part == GraphPart.full && l.from == existing);
        lines
          ..add(GraphLine(existing, existing, GraphPart.top, colors[existing]))
          ..add(GraphLine(existing, lane, GraphPart.bottom, colors[existing]))
          ..add(GraphLine(lane, lane, GraphPart.bottom, color));
      } else {
        lanes[lane] = first;
        lines.add(GraphLine(lane, lane, GraphPart.bottom, color));
      }
      for (final parent in commit.parents.skip(1)) {
        var target = lanes.indexOf(parent);
        if (target < 0) {
          target = freeSlot();
          lanes[target] = parent;
          colors[target] = nextColor++;
        }
        lines.add(GraphLine(lane, target, GraphPart.bottom, colors[target]));
      }
    }

    var width = lane + 1;
    for (final l in lines) {
      if (l.from + 1 > width) width = l.from + 1;
      if (l.to + 1 > width) width = l.to + 1;
    }
    rows.add(GraphRow(lane, color, lines, width));

    while (lanes.isNotEmpty && lanes.last == null) {
      lanes.removeLast();
      colors.removeLast();
    }
  }
  return rows;
}
