import 'package:easygit/git/diff.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> apply(List<String> a, List<String> b, List<DiffOp> ops) => [
        for (final op in ops)
          if (op.type == DiffOpType.equal) a[op.a] else if (op.type == DiffOpType.insert) b[op.b],
      ];

  test('identical input yields only equal ops', () {
    final a = ['x', 'y', 'z'];
    final ops = diffLines(a, a);
    expect(ops.every((o) => o.type == DiffOpType.equal), isTrue);
    expect(ops.length, 3);
  });

  test('edit script transforms old lines into new lines', () {
    final cases = [
      (['a', 'b', 'c', 'a', 'b', 'b', 'a'], ['c', 'b', 'a', 'b', 'a', 'c']),
      (<String>[], ['1', '2']),
      (['1', '2'], <String>[]),
      (['keep', 'old', 'keep2'], ['keep', 'new', 'keep2']),
      (['a', 'b', 'c', 'd'], ['a', 'x', 'c', 'y', 'd', 'z']),
    ];
    for (final (a, b) in cases) {
      final ops = diffLines(a, b);
      expect(apply(a, b, ops), b);
      final deleted = ops.where((o) => o.type != DiffOpType.insert).map((o) => a[o.a]).toList();
      expect(deleted, a);
    }
  });

  test('side-by-side pairs a replaced line as changed', () {
    final a = ['keep', 'old', 'keep2'];
    final b = ['keep', 'new', 'keep2'];
    final rows = buildSideBySide(a, b, diffLines(a, b));
    expect(rows.map((r) => r.type), [DiffRowType.equal, DiffRowType.changed, DiffRowType.equal]);
    expect(rows[1].left, 'old');
    expect(rows[1].right, 'new');
  });

  test('splitLines handles CRLF and trailing newline', () {
    expect(splitLines('a\r\nb\r\n'), ['a', 'b']);
    expect(splitLines(''), isEmpty);
  });
}
