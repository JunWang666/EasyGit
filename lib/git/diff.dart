import 'dart:typed_data';

enum DiffOpType { equal, delete, insert }

/// One step of an edit script. [a] / [b] index into the old / new lines.
class DiffOp {
  const DiffOp(this.type, this.a, this.b);

  final DiffOpType type;
  final int a;
  final int b;
}

enum DiffRowType { equal, changed, deleted, inserted }

/// A row of a side-by-side diff.
class DiffRow {
  const DiffRow(this.type, {this.leftNo, this.left, this.rightNo, this.right});

  final DiffRowType type;
  final int? leftNo;
  final String? left;
  final int? rightNo;
  final String? right;
}

/// A row of a unified diff.
class UnifiedLine {
  const UnifiedLine(this.type, this.text, {this.oldNo, this.newNo});

  /// [DiffRowType.deleted], [DiffRowType.inserted] or [DiffRowType.equal].
  final DiffRowType type;
  final String text;
  final int? oldNo;
  final int? newNo;
}

List<String> splitLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return [for (final l in lines) l.endsWith('\r') ? l.substring(0, l.length - 1) : l];
}

bool looksBinary(String? text) => text != null && text.contains('\u0000');

/// Line diff using Myers' O(ND) algorithm with common prefix/suffix trimming.
List<DiffOp> diffLines(List<String> a, List<String> b) {
  var start = 0;
  while (start < a.length && start < b.length && a[start] == b[start]) {
    start++;
  }
  var endA = a.length;
  var endB = b.length;
  while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
    endA--;
    endB--;
  }
  return [
    for (var i = 0; i < start; i++) DiffOp(DiffOpType.equal, i, i),
    ..._myers(a, b, start, endA, start, endB),
    for (var i = 0; i < a.length - endA; i++) DiffOp(DiffOpType.equal, endA + i, endB + i),
  ];
}

const _maxEditDistance = 2000;

List<DiffOp> _myers(List<String> a, List<String> b, int a0, int a1, int b0, int b1) {
  final n = a1 - a0;
  final m = b1 - b0;
  List<DiffOp> replaceAll() => [
        for (var i = a0; i < a1; i++) DiffOp(DiffOpType.delete, i, -1),
        for (var j = b0; j < b1; j++) DiffOp(DiffOpType.insert, -1, j),
      ];
  if (n == 0 || m == 0) return replaceAll();

  final max = n + m;
  final offset = max + 1;
  final v = Int32List(2 * max + 3);
  // trace[d] holds v (k in [-d-1, d+1]) as it was before step d.
  final trace = <Int32List>[];

  for (var d = 0; d <= max; d++) {
    if (d > _maxEditDistance) return replaceAll();
    final snap = Int32List(2 * d + 3);
    for (var k = -d - 1; k <= d + 1; k++) {
      snap[k + d + 1] = v[k + offset];
    }
    trace.add(snap);
    for (var k = -d; k <= d; k += 2) {
      var x = (k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset]))
          ? v[k + 1 + offset]
          : v[k - 1 + offset] + 1;
      var y = x - k;
      while (x < n && y < m && a[a0 + x] == b[b0 + y]) {
        x++;
        y++;
      }
      v[k + offset] = x;
      if (x >= n && y >= m) return _backtrack(trace, n, m, a0, b0);
    }
  }
  return replaceAll();
}

List<DiffOp> _backtrack(List<Int32List> trace, int n, int m, int a0, int b0) {
  final ops = <DiffOp>[];
  var x = n;
  var y = m;
  for (var d = trace.length - 1; d >= 0; d--) {
    final snap = trace[d];
    int at(int k) => snap[k + d + 1];
    final k = x - y;
    final prevK = (k == -d || (k != d && at(k - 1) < at(k + 1))) ? k + 1 : k - 1;
    final prevX = at(prevK);
    final prevY = prevX - prevK;
    while (x > prevX && y > prevY) {
      ops.add(DiffOp(DiffOpType.equal, a0 + x - 1, b0 + y - 1));
      x--;
      y--;
    }
    if (d > 0) {
      if (x == prevX) {
        ops.add(DiffOp(DiffOpType.insert, -1, b0 + prevY));
      } else {
        ops.add(DiffOp(DiffOpType.delete, a0 + prevX, -1));
      }
    }
    x = prevX;
    y = prevY;
  }
  return ops.reversed.toList();
}

/// Pairs deletions and insertions into aligned side-by-side rows.
List<DiffRow> buildSideBySide(List<String> a, List<String> b, List<DiffOp> ops) {
  final rows = <DiffRow>[];
  var i = 0;
  while (i < ops.length) {
    final op = ops[i];
    if (op.type == DiffOpType.equal) {
      rows.add(DiffRow(DiffRowType.equal,
          leftNo: op.a + 1, left: a[op.a], rightNo: op.b + 1, right: b[op.b]));
      i++;
      continue;
    }
    final dels = <int>[];
    final ins = <int>[];
    while (i < ops.length && ops[i].type != DiffOpType.equal) {
      if (ops[i].type == DiffOpType.delete) {
        dels.add(ops[i].a);
      } else {
        ins.add(ops[i].b);
      }
      i++;
    }
    final paired = dels.length < ins.length ? dels.length : ins.length;
    for (var p = 0; p < paired; p++) {
      rows.add(DiffRow(DiffRowType.changed,
          leftNo: dels[p] + 1, left: a[dels[p]], rightNo: ins[p] + 1, right: b[ins[p]]));
    }
    for (var p = paired; p < dels.length; p++) {
      rows.add(DiffRow(DiffRowType.deleted, leftNo: dels[p] + 1, left: a[dels[p]]));
    }
    for (var p = paired; p < ins.length; p++) {
      rows.add(DiffRow(DiffRowType.inserted, rightNo: ins[p] + 1, right: b[ins[p]]));
    }
  }
  return rows;
}

List<UnifiedLine> buildUnified(List<String> a, List<String> b, List<DiffOp> ops) {
  final lines = <UnifiedLine>[];
  var i = 0;
  while (i < ops.length) {
    final op = ops[i];
    if (op.type == DiffOpType.equal) {
      lines.add(UnifiedLine(DiffRowType.equal, a[op.a], oldNo: op.a + 1, newNo: op.b + 1));
      i++;
      continue;
    }
    final ins = <int>[];
    while (i < ops.length && ops[i].type != DiffOpType.equal) {
      final o = ops[i];
      if (o.type == DiffOpType.delete) {
        lines.add(UnifiedLine(DiffRowType.deleted, a[o.a], oldNo: o.a + 1));
      } else {
        ins.add(o.b);
      }
      i++;
    }
    for (final j in ins) {
      lines.add(UnifiedLine(DiffRowType.inserted, b[j], newNo: j + 1));
    }
  }
  return lines;
}

/// Indices where a run of non-equal rows starts.
List<int> changeStarts<T>(List<T> rows, bool Function(T row) isEqual) {
  final starts = <int>[];
  for (var i = 0; i < rows.length; i++) {
    if (!isEqual(rows[i]) && (i == 0 || isEqual(rows[i - 1]))) starts.add(i);
  }
  return starts;
}
