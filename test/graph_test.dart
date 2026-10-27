import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/graph.dart';
import 'package:easygit/git/models.dart';
import 'package:flutter_test/flutter_test.dart';

CommitInfo _c(String hash, List<String> parents) => CommitInfo(
      hash: hash,
      parents: parents,
      author: 'a',
      email: 'a@example.com',
      date: DateTime(2026),
      subject: hash,
    );

void main() {
  test('linear history stays in lane 0', () {
    final rows = buildGraph([_c('c', ['b']), _c('b', ['a']), _c('a', [])]);
    expect(rows.map((r) => r.lane), [0, 0, 0]);
    expect(rows.every((r) => r.width == 1), isTrue);
  });

  test('merge opens a second lane that converges on the fork point', () {
    // m merges f into b; f and b both come from a.
    final rows = buildGraph([
      _c('m', ['b', 'f']),
      _c('f', ['a']),
      _c('b', ['a']),
      _c('a', []),
    ]);
    expect(rows[0].lane, 0);
    expect(rows[0].lines.where((l) => l.part == GraphPart.bottom).map((l) => l.to), [0, 1]);
    expect(rows[1].lane, 1);
    expect(rows[2].lane, 0);
    // Lane 1 is pulled back into lane 0 below b, so a sits in lane 0.
    expect(
        rows[2].lines.any((l) => l.part == GraphPart.bottom && l.from == 1 && l.to == 0), isTrue);
    expect(rows[3].lane, 0);
    expect(rows[3].width, 1);
  });

  test('parses decorations from --decorate=full', () {
    final labels = GitRepository.parseDecorations(
        'HEAD -> refs/heads/main, refs/remotes/origin/main, refs/remotes/origin/HEAD, tag: refs/tags/v1');
    expect(labels.map((l) => l.name), ['main', 'origin/main', 'v1']);
    expect(labels.first.isCurrent, isTrue);
    expect(labels.last.type, RefLabelType.tag);
  });

  test('parses git worktree list --porcelain', () {
    final w = GitRepository.parseWorktrees('worktree C:/src/app\nHEAD aaa\nbranch refs/heads/main\n\n'
        'worktree C:/src/app-fix\nHEAD bbb\ndetached\nlocked\n\n'
        'worktree C:/gone\nHEAD ccc\nbranch refs/heads/old\nprunable gitdir file points to non-existent location\n');
    expect(w.length, 3);
    expect(w[0].isMain, isTrue);
    expect(w[0].branch, 'main');
    expect(w[1].branch, isNull);
    expect(w[1].locked, isTrue);
    expect(w[1].name, 'app-fix');
    expect(w[2].prunable, isTrue);
  });

  test('parses diff-tree name-status output', () {
    final files = GitRepository.parseNameStatus('M\x00lib/a.dart\x00R100\x00old.txt\x00new.txt\x00');
    expect(files.length, 2);
    expect(files[0].kind, ChangeKind.modified);
    expect(files[1].kind, ChangeKind.renamed);
    expect(files[1].oldPath, 'old.txt');
    expect(files[1].path, 'new.txt');
  });
}
