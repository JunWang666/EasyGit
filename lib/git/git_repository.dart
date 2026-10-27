import 'dart:convert';
import 'dart:io';

import 'git_runner.dart';
import 'lfs.dart';
import 'models.dart';

enum ResetMode { soft, mixed, hard, keep }

/// High-level git operations on one repository.
class GitRepository {
  GitRepository._(this.root, this.gitDir, this._git);

  /// Absolute path of the working tree root.
  final String root;

  /// Absolute path of the `.git` directory.
  final String gitDir;
  final GitRunner _git;

  set onLog(void Function(GitCommandLog log)? callback) => _git.onLog = callback;

  String get name =>
      root.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? root;

  /// Opens the repository that contains [dir].
  static Future<GitRepository> open(String dir) async {
    final root = (await GitRunner(dir).run(['rev-parse', '--show-toplevel'])).trim();
    final gitDir = (await GitRunner(root).run(['rev-parse', '--absolute-git-dir'])).trim();
    return GitRepository._(root, gitDir, GitRunner(root));
  }

  static Future<void> init(String dir) => GitRunner(dir).run(['init']);

  static Future<void> clone(String url, String parentDir, String folder) =>
      GitRunner(parentDir).run(['clone', url, folder]);

  // ---------------------------------------------------------------- status

  Future<RepoStatus> status() async {
    final out = await _git.run(
        ['status', '--porcelain=v2', '--branch', '-z', '--untracked-files=all']);
    final parts = out.split('\x00');
    String? branch;
    String? oid;
    String? upstream;
    var ahead = 0;
    var behind = 0;
    final changes = <FileChange>[];

    for (var i = 0; i < parts.length; i++) {
      final line = parts[i];
      if (line.isEmpty) continue;
      if (line.startsWith('# ')) {
        final rest = line.substring(2);
        if (rest.startsWith('branch.oid ')) {
          final v = rest.substring(11);
          oid = v == '(initial)' ? null : v;
        } else if (rest.startsWith('branch.head ')) {
          final v = rest.substring(12);
          branch = v == '(detached)' ? null : v;
        } else if (rest.startsWith('branch.upstream ')) {
          upstream = rest.substring(16);
        } else if (rest.startsWith('branch.ab ')) {
          final m = RegExp(r'\+(\d+) -(\d+)').firstMatch(rest);
          if (m != null) {
            ahead = int.parse(m[1]!);
            behind = int.parse(m[2]!);
          }
        }
        continue;
      }
      final type = line[0];
      if (type == '1') {
        final f = _splitFields(line, 8);
        changes.add(_change(f.fields[1], f.rest));
      } else if (type == '2') {
        final f = _splitFields(line, 9);
        final orig = i + 1 < parts.length ? parts[++i] : null;
        changes.add(_change(f.fields[1], f.rest, oldPath: orig));
      } else if (type == 'u') {
        final f = _splitFields(line, 10);
        changes.add(FileChange(path: f.rest, kind: ChangeKind.conflicted, unstaged: true));
      } else if (type == '?') {
        changes.add(FileChange(
            path: line.substring(2), kind: ChangeKind.untracked, unstaged: true));
      }
    }
    changes.sort((a, b) => a.path.compareTo(b.path));
    return RepoStatus(
      branch: branch,
      headHash: oid,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      changes: changes,
      state: await _repoState(),
    );
  }

  static ({List<String> fields, String rest}) _splitFields(String line, int n) {
    final fields = <String>[];
    var start = 0;
    for (var k = 0; k < n; k++) {
      final sp = line.indexOf(' ', start);
      if (sp < 0) break;
      fields.add(line.substring(start, sp));
      start = sp + 1;
    }
    while (fields.length < 2) {
      fields.add('..');
    }
    return (fields: fields, rest: line.substring(start));
  }

  static FileChange _change(String xy, String path, {String? oldPath}) {
    final x = xy[0];
    final y = xy.length > 1 ? xy[1] : '.';
    final ChangeKind kind;
    if (x == 'D' || y == 'D') {
      kind = ChangeKind.deleted;
    } else if (x == 'A') {
      kind = ChangeKind.added;
    } else if (x == 'R' || y == 'R') {
      kind = ChangeKind.renamed;
    } else if (x == 'C') {
      kind = ChangeKind.copied;
    } else if (x == 'T' || y == 'T') {
      kind = ChangeKind.typeChanged;
    } else {
      kind = ChangeKind.modified;
    }
    return FileChange(
        path: path, oldPath: oldPath, kind: kind, staged: x != '.', unstaged: y != '.');
  }

  Future<RepoState> _repoState() async {
    if (await File('$gitDir/MERGE_HEAD').exists()) return RepoState.merging;
    if (await Directory('$gitDir/rebase-merge').exists() ||
        await Directory('$gitDir/rebase-apply').exists()) {
      return RepoState.rebasing;
    }
    if (await File('$gitDir/CHERRY_PICK_HEAD').exists()) return RepoState.cherryPicking;
    if (await File('$gitDir/REVERT_HEAD').exists()) return RepoState.reverting;
    return RepoState.normal;
  }

  // ---------------------------------------------------------------- refs

  Future<List<GitRef>> refs() async {
    final out = await _git.run([
      'for-each-ref',
      '--format=%(refname)%1f%(objectname)%1f%(*objectname)%1f%(upstream:short)'
          '%1f%(upstream:track)%1f%(HEAD)%1f%(creatordate:unix)%1f%(contents:subject)',
      'refs/heads',
      'refs/remotes',
      'refs/tags',
    ]);
    final result = <GitRef>[];
    for (final line in const LineSplitter().convert(out)) {
      final f = line.split('\x1f');
      if (f.length < 6) continue;
      final full = f[0];
      final RefType type;
      final String name;
      if (full.startsWith('refs/heads/')) {
        type = RefType.local;
        name = full.substring(11);
      } else if (full.startsWith('refs/remotes/')) {
        if (full.endsWith('/HEAD')) continue;
        type = RefType.remote;
        name = full.substring(13);
      } else if (full.startsWith('refs/tags/')) {
        type = RefType.tag;
        name = full.substring(10);
      } else {
        continue;
      }
      final track = f[4];
      result.add(GitRef(
        fullName: full,
        name: name,
        hash: f[2].isNotEmpty ? f[2] : f[1],
        type: type,
        upstream: f[3].isEmpty ? null : f[3],
        ahead: int.tryParse(RegExp(r'ahead (\d+)').firstMatch(track)?[1] ?? '') ?? 0,
        behind: int.tryParse(RegExp(r'behind (\d+)').firstMatch(track)?[1] ?? '') ?? 0,
        upstreamGone: track.contains('gone'),
        isHead: f[5] == '*',
        date: f.length > 6 && int.tryParse(f[6]) != null
            ? DateTime.fromMillisecondsSinceEpoch(int.parse(f[6]) * 1000)
            : null,
        subject: f.length > 7 ? f.sublist(7).join(' ') : '',
      ));
    }
    return result;
  }

  Future<List<String>> remotes() async {
    final out = await _git.run(['remote']);
    return const LineSplitter().convert(out).where((s) => s.trim().isNotEmpty).toList();
  }

  /// Fetch URL of each remote, in `git remote` order.
  Future<Map<String, String>> remoteUrls() async {
    final out = await _git.run(['remote', '-v']);
    final urls = <String, String>{};
    for (final line in const LineSplitter().convert(out)) {
      final m = RegExp(r'^(\S+)\s+(.+?)\s+\(fetch\)$').firstMatch(line);
      if (m != null) urls[m[1]!] = m[2]!;
    }
    return urls;
  }

  Future<void> addRemote(String name, String url) =>
      _git.run(['remote', 'add', name, url], log: true);

  Future<void> setRemoteUrl(String name, String url) =>
      _git.run(['remote', 'set-url', name, url], log: true);

  Future<void> renameRemote(String from, String to) =>
      _git.run(['remote', 'rename', from, to], log: true);

  Future<void> removeRemote(String name) => _git.run(['remote', 'remove', name], log: true);

  /// The remote's default branch (`main`), if `refs/remotes/<remote>/HEAD` is known.
  Future<String?> remoteDefaultBranch(String remote) async {
    try {
      final out = (await _git.run(['symbolic-ref', '--short', 'refs/remotes/$remote/HEAD'])).trim();
      return out.startsWith('$remote/') ? out.substring(remote.length + 1) : null;
    } on GitException {
      return null;
    }
  }

  // ---------------------------------------------------------------- log

  static const _logFormat = '%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e';

  /// Commits in topological order. [branch] null means all branches and tags.
  Future<List<CommitInfo>> log({String? branch, int limit = 5000}) async {
    final String out;
    try {
      out = await _git.run([
        'log',
        '--topo-order',
        '--decorate=full',
        '--format=$_logFormat',
        '-n',
        '$limit',
        if (branch == null) ...['--branches', '--remotes', '--tags', 'HEAD'] else branch,
        '--',
      ]);
    } on GitException {
      // A repository without commits has no HEAD to log.
      if ((await refs()).isEmpty) return const [];
      rethrow;
    }
    final commits = <CommitInfo>[];
    for (var record in out.split('\x1e')) {
      record = record.trimLeft();
      if (record.isEmpty) continue;
      final f = record.split('\x1f');
      if (f.length < 7) continue;
      commits.add(CommitInfo(
        hash: f[0],
        parents: f[1].trim().isEmpty ? const [] : f[1].trim().split(' '),
        author: f[2],
        email: f[3],
        date: DateTime.fromMillisecondsSinceEpoch((int.tryParse(f[4]) ?? 0) * 1000),
        refs: parseDecorations(f[5]),
        subject: f[6],
      ));
    }
    return commits;
  }

  /// Parses `%D` output produced with `--decorate=full`.
  static List<RefLabel> parseDecorations(String decorations) {
    if (decorations.trim().isEmpty) return const [];
    final labels = <RefLabel>[];
    for (var part in decorations.split(', ')) {
      part = part.trim();
      var current = false;
      if (part == 'HEAD') {
        labels.add(const RefLabel('HEAD', RefLabelType.head));
        continue;
      }
      if (part.startsWith('HEAD -> ')) {
        current = true;
        part = part.substring(8);
      }
      if (part.startsWith('tag: ')) part = part.substring(5);
      if (part.startsWith('refs/heads/')) {
        labels.add(RefLabel(part.substring(11), RefLabelType.local, isCurrent: current));
      } else if (part.startsWith('refs/remotes/')) {
        if (part.endsWith('/HEAD')) continue;
        labels.add(RefLabel(part.substring(13), RefLabelType.remote));
      } else if (part.startsWith('refs/tags/')) {
        labels.add(RefLabel(part.substring(10), RefLabelType.tag));
      } else if (!part.startsWith('refs/')) {
        labels.add(RefLabel(part, RefLabelType.local, isCurrent: current));
      }
    }
    // Current branch first, then local, remote, tags.
    labels.sort((a, b) {
      if (a.isCurrent != b.isCurrent) return a.isCurrent ? -1 : 1;
      return a.type.index.compareTo(b.type.index);
    });
    return labels;
  }

  Future<CommitDetails> commitDetails(String hash) async {
    final out = await _git.run([
      'show',
      '-s',
      '--decorate=full',
      '--format=%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1f%b%x1f%cn%x1f%ct',
      hash,
    ]);
    final f = out.split('\x1f');
    if (f.length < 10) throw GitException('git show $hash', 'Unexpected output');
    final info = CommitInfo(
      hash: f[0].trim(),
      parents: f[1].trim().isEmpty ? const [] : f[1].trim().split(' '),
      author: f[2],
      email: f[3],
      date: DateTime.fromMillisecondsSinceEpoch((int.tryParse(f[4]) ?? 0) * 1000),
      refs: parseDecorations(f[5]),
      subject: f[6],
    );
    final parent = info.parents.firstOrNull;
    final files = await _git.run([
      'diff-tree',
      '--no-commit-id',
      '-r',
      '-z',
      '-M',
      '--name-status',
      if (parent == null) '--root' else parent,
      info.hash,
    ]);
    return CommitDetails(
      info: info,
      body: f[7].trim(),
      committer: f[8],
      commitDate: DateTime.fromMillisecondsSinceEpoch((int.tryParse(f[9].trim()) ?? 0) * 1000),
      files: parseNameStatus(files),
    );
  }

  static List<FileChange> parseNameStatus(String out) {
    final p = out.split('\x00');
    final result = <FileChange>[];
    var i = 0;
    while (i < p.length) {
      final s = p[i];
      if (s.isEmpty) {
        i++;
        continue;
      }
      final letter = s[0];
      if (letter == 'R' || letter == 'C') {
        if (i + 2 >= p.length) break;
        result.add(FileChange(
            path: p[i + 2], oldPath: p[i + 1], kind: changeKindFromLetter(letter)));
        i += 3;
      } else {
        if (i + 1 >= p.length) break;
        result.add(FileChange(path: p[i + 1], kind: changeKindFromLetter(letter)));
        i += 2;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- contents

  /// File content at a revision, or null if it does not exist there.
  Future<String?> fileAt(String rev, String path) async {
    try {
      return await _git.run(['show', '$rev:$path']);
    } on GitException {
      return null;
    }
  }

  /// Content of a file in the working tree, or null if it does not exist.
  Future<String?> readWorkingFile(String path) async {
    final file = File('$root/$path');
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return const Utf8Decoder(allowMalformed: true).convert(bytes);
  }

  Future<String> lastCommitMessage() async =>
      (await _git.run(['log', '-1', '--format=%B'])).trim();

  // ---------------------------------------------------------------- local changes

  /// Commits exactly [files] (like the IDE's commit dialog: no staging area).
  Future<void> commit(String message, List<FileChange> files, {bool amend = false}) async {
    final untracked = [for (final f in files) if (f.isUntracked) f.path];
    if (untracked.isNotEmpty) await _git.run(['add', '--', ...untracked], log: true);
    final paths = <String>{
      for (final f in files) ...[f.path, if (f.oldPath != null) f.oldPath!],
    };
    await _git.run([
      'commit',
      if (amend) '--amend',
      if (paths.isEmpty) '--only',
      '-F',
      '-',
      if (paths.isNotEmpty) ...['--', ...paths],
    ], stdin: message, log: true);
  }

  /// Reverts local changes of [files] to HEAD.
  Future<void> rollback(List<FileChange> files) async {
    final restore = <String>[];
    final unstage = <String>[];
    for (final f in files) {
      switch (f.kind) {
        case ChangeKind.untracked:
          break;
        case ChangeKind.added:
        case ChangeKind.copied:
          unstage.add(f.path);
        case ChangeKind.renamed:
          unstage.add(f.path);
          if (f.oldPath != null) restore.add(f.oldPath!);
        default:
          restore.add(f.path);
      }
    }
    if (unstage.isNotEmpty) {
      await _git.run(['rm', '--cached', '--quiet', '-r', '--', ...unstage], log: true);
    }
    if (restore.isNotEmpty) {
      await _git.run(
          ['restore', '--source=HEAD', '--staged', '--worktree', '--', ...restore],
          log: true);
    }
  }

  Future<void> addToVcs(List<String> paths) => _git.run(['add', '--', ...paths], log: true);

  Future<void> stash(String message) =>
      _git.run(['stash', 'push', '--include-untracked', if (message.isNotEmpty) ...['-m', message]],
          log: true);

  Future<void> stashPop([String? ref]) =>
      _git.run(['stash', 'pop', if (ref != null) ref], log: true);

  Future<void> stashApply(String ref) => _git.run(['stash', 'apply', ref], log: true);

  Future<void> stashDrop(String ref) => _git.run(['stash', 'drop', ref], log: true);

  Future<List<StashEntry>> stashes() async {
    final out = await _git.run(['stash', 'list', '--format=%gd%x1f%H%x1f%ct%x1f%s']);
    return [
      for (final line in const LineSplitter().convert(out))
        if (line.split('\x1f') case [final ref, final hash, final time, final message, ...])
          StashEntry(
            ref: ref,
            hash: hash,
            date: DateTime.fromMillisecondsSinceEpoch((int.tryParse(time) ?? 0) * 1000),
            message: message,
          ),
    ];
  }

  // ---------------------------------------------------------------- worktrees

  Future<List<WorktreeInfo>> worktrees() async =>
      parseWorktrees(await _git.run(['worktree', 'list', '--porcelain']));

  /// Parses `git worktree list --porcelain`. The first entry is the main worktree.
  static List<WorktreeInfo> parseWorktrees(String out) {
    final result = <WorktreeInfo>[];
    for (final block in out.replaceAll('\r\n', '\n').split('\n\n')) {
      String? path;
      var head = '';
      String? branch;
      var bare = false;
      var locked = false;
      var prunable = false;
      for (final line in block.split('\n')) {
        if (line.startsWith('worktree ')) {
          path = line.substring(9);
        } else if (line.startsWith('HEAD ')) {
          head = line.substring(5);
        } else if (line.startsWith('branch ')) {
          final ref = line.substring(7);
          branch = ref.startsWith('refs/heads/') ? ref.substring(11) : ref;
        } else if (line == 'bare') {
          bare = true;
        } else if (line == 'locked' || line.startsWith('locked ')) {
          locked = true;
        } else if (line == 'prunable' || line.startsWith('prunable ')) {
          prunable = true;
        }
      }
      if (path == null) continue;
      result.add(WorktreeInfo(
        path: path,
        head: head,
        branch: branch,
        isMain: result.isEmpty,
        isBare: bare,
        locked: locked,
        prunable: prunable,
      ));
    }
    return result;
  }

  /// Adds a worktree at [path]. With [newBranch], creates that branch from
  /// [commitish]; otherwise checks out [commitish] (an existing branch).
  Future<void> addWorktree(String path, String commitish, {String? newBranch}) => _git.run([
        'worktree',
        'add',
        if (newBranch != null) ...['-b', newBranch],
        path,
        commitish,
      ], log: true);

  Future<void> removeWorktree(String path, {bool force = false}) =>
      _git.run(['worktree', 'remove', if (force) '--force', path], log: true);

  Future<void> pruneWorktrees() => _git.run(['worktree', 'prune'], log: true);

  // ---------------------------------------------------------------- remotes

  Future<void> fetch() => _git.run(['fetch', '--all', '--prune'], log: true);

  Future<void> pull({bool rebase = false}) =>
      _git.run(['pull', '--no-edit', if (rebase) '--rebase'], log: true);

  /// Pushes the current branch, setting an upstream on first push.
  Future<void> push({bool force = false}) async {
    final st = await status();
    if (st.branch == null) {
      throw const GitException('git push', 'Cannot push: HEAD is detached.');
    }
    if (st.upstream != null) {
      await _git.run(['push', if (force) '--force-with-lease'], log: true);
      return;
    }
    await _git.run(['push', '-u', await _defaultRemote(), st.branch!], log: true);
  }

  Future<void> pushBranch(GitRef ref) async {
    final upstream = ref.upstream;
    if (upstream != null && upstream.contains('/')) {
      final slash = upstream.indexOf('/');
      await _git.run(
          ['push', upstream.substring(0, slash), '${ref.name}:${upstream.substring(slash + 1)}'],
          log: true);
    } else {
      await _git.run(['push', '-u', await _defaultRemote(), ref.name], log: true);
    }
  }

  Future<String> _defaultRemote() async {
    final all = await remotes();
    if (all.isEmpty) throw const GitException('git push', 'No remote is configured.');
    return all.contains('origin') ? 'origin' : all.first;
  }

  // ---------------------------------------------------------------- branches

  Future<void> checkout(String ref) => _git.run(['checkout', ref], log: true);

  Future<void> checkoutRevision(String rev) =>
      _git.run(['checkout', '--detach', rev], log: true);

  /// Checks out a remote branch, creating a tracking local branch if needed.
  Future<void> checkoutRemote(GitRef remote, List<GitRef> all) async {
    final local = remote.branchName;
    final exists = all.any((r) => r.type == RefType.local && r.name == local);
    if (exists) {
      await checkout(local);
    } else {
      await _git.run(['checkout', '-b', local, '--track', remote.name], log: true);
    }
  }

  Future<void> createBranch(String name, String startPoint, {required bool checkout}) =>
      _git.run(checkout ? ['checkout', '-b', name, startPoint] : ['branch', name, startPoint],
          log: true);

  Future<void> renameBranch(String from, String to) =>
      _git.run(['branch', '-m', from, to], log: true);

  Future<void> deleteBranch(GitRef ref, {bool force = false}) {
    if (ref.type == RefType.remote) {
      return _git.run(['push', ref.remote, '--delete', ref.branchName], log: true);
    }
    if (ref.type == RefType.tag) return _git.run(['tag', '-d', ref.name], log: true);
    return _git.run(['branch', force ? '-D' : '-d', ref.name], log: true);
  }

  Future<void> merge(String ref) => _git.run(['merge', '--no-edit', ref], log: true);

  Future<void> rebase(String onto) => _git.run(['rebase', onto], log: true);

  Future<void> abortOperation(RepoState state) async {
    final args = switch (state) {
      RepoState.merging => ['merge', '--abort'],
      RepoState.rebasing => ['rebase', '--abort'],
      RepoState.cherryPicking => ['cherry-pick', '--abort'],
      RepoState.reverting => ['revert', '--abort'],
      RepoState.normal => null,
    };
    if (args != null) await _git.run(args, log: true);
  }

  Future<void> continueOperation(RepoState state) async {
    final args = switch (state) {
      RepoState.merging => ['commit', '--no-edit'],
      RepoState.rebasing => ['rebase', '--continue'],
      RepoState.cherryPicking => ['cherry-pick', '--continue'],
      RepoState.reverting => ['revert', '--continue'],
      RepoState.normal => null,
    };
    if (args != null) await _git.run(args, log: true);
  }

  // ---------------------------------------------------------------- commits

  Future<void> cherryPick(String hash) => _git.run(['cherry-pick', hash], log: true);

  Future<void> revert(String hash) => _git.run(['revert', '--no-edit', hash], log: true);

  Future<void> reset(String hash, ResetMode mode) =>
      _git.run(['reset', '--${mode.name}', hash], log: true);

  Future<void> createTag(String name, String hash) => _git.run(['tag', name, hash], log: true);

  // ---------------------------------------------------------------- Git LFS

  static Future<String?>? _lfsVersion;

  /// The git-lfs version line, or null when git-lfs is not installed.
  static Future<String?> lfsVersion() => _lfsVersion ??= () async {
        try {
          final out = await GitRunner(Directory.systemTemp.path).run(['lfs', 'version']);
          return out.trim();
        } on GitException {
          return null;
        }
      }();

  /// Whether the root .gitattributes routes any path through LFS.
  Future<bool> usesLfs() async {
    final file = File('$root/.gitattributes');
    if (!await file.exists()) return false;
    return (await file.readAsString()).contains('filter=lfs');
  }

  /// Patterns in the root .gitattributes that use LFS, e.g. `*.psd`.
  Future<List<String>> lfsPatterns() async {
    final file = File('$root/.gitattributes');
    if (!await file.exists()) return const [];
    return [
      for (final line in const LineSplitter().convert(await file.readAsString()))
        if (line.contains('filter=lfs') && !line.trimLeft().startsWith('#'))
          line.trim().split(RegExp(r'\s+')).first,
    ];
  }

  /// Whether the LFS pre-push hook is installed for this repository.
  Future<bool> lfsHooksInstalled() async {
    try {
      var path = (await _git.run(['rev-parse', '--git-path', 'hooks/pre-push'])).trim();
      if (!File(path).isAbsolute) path = '$root/$path';
      final file = File(path);
      return await file.exists() && (await file.readAsString()).contains('git lfs');
    } on GitException {
      return false;
    }
  }

  Future<void> lfsInstallHooks() => _git.run(['lfs', 'install', '--local'], log: true);

  Future<List<LfsFile>> lfsFiles() async {
    try {
      return parseLfsFilesJson(await _git.run(['lfs', 'ls-files', '--json']));
    } on GitException {
      return const [];
    } on FormatException {
      return const [];
    }
  }

  Future<LfsEnv> lfsEnv() async {
    try {
      return LfsEnv.parse(await _git.run(['lfs', 'env']));
    } on GitException {
      return const LfsEnv();
    }
  }

  /// Which of [paths] are stored with LFS, from .gitattributes.
  Future<Set<String>> lfsTrackedPaths(Iterable<String> paths) async {
    final list = paths.toList();
    if (list.isEmpty) return const {};
    final out = await _git.run(['check-attr', '-z', '--stdin', 'filter'],
        stdin: '${list.join('\x00')}\x00');
    return {
      for (final e in parseCheckAttrZ(out).entries)
        if (e.value['filter'] == 'lfs') e.key,
    };
  }

  Future<void> lfsTrack(List<String> patterns) =>
      _git.run(['lfs', 'track', ...patterns], log: true);

  /// Downloads LFS content into the working tree; [paths] limits it.
  Future<void> lfsPull([List<String>? paths]) => _git.run([
        'lfs',
        'pull',
        if (paths != null && paths.isNotEmpty) '--include=${paths.map(_lfsEscape).join(',')}',
      ], log: true);

  /// Downloads the object of [path] as of [rev] into the local LFS store.
  Future<void> lfsFetch(String remote, String rev, String path) =>
      _git.run(['lfs', 'fetch', '--include=${_lfsEscape(path)}', remote, rev], log: true);

  static String _lfsEscape(String path) => path.replaceAll(',', r'\,');

  Future<LfsServerConfig> lfsServerConfig() async {
    Future<String?> get(List<String> args) async {
      try {
        final v = (await _git.run(['config', ...args, '--get', 'lfs.url'])).trim();
        return v.isEmpty ? null : v;
      } on GitException {
        return null;
      }
    }

    final hasShared = await File('$root/.lfsconfig').exists();
    return LfsServerConfig(
      localUrl: await get(['--local']),
      sharedUrl: hasShared ? await get(['-f', '.lfsconfig']) : null,
      effective: (await lfsEnv()).endpoint,
    );
  }

  /// Sets where the LFS server URL comes from. With [LfsUrlSource.shared]
  /// the change is written to .lfsconfig, which then shows up as a change
  /// to commit.
  Future<void> setLfsServer(LfsUrlSource source, String url) async {
    Future<void> unset(List<String> args) async {
      try {
        await _git.run(['config', ...args, '--unset', 'lfs.url']);
      } on GitException {
        // Not set.
      }
    }

    final shared = File('$root/.lfsconfig');
    switch (source) {
      case LfsUrlSource.automatic:
        await unset(['--local']);
        if (await shared.exists()) {
          await unset(['-f', '.lfsconfig']);
          // Remove the file if nothing but empty sections is left.
          final rest = (await shared.readAsString())
              .split('\n')
              .where((l) => l.trim().isNotEmpty && !RegExp(r'^\s*\[.*\]\s*$').hasMatch(l));
          if (rest.isEmpty) await shared.delete();
        }
      case LfsUrlSource.shared:
        await unset(['--local']);
        await _git.run(['config', '-f', '.lfsconfig', 'lfs.url', url], log: true);
      case LfsUrlSource.local:
        await _git.run(['config', '--local', 'lfs.url', url], log: true);
    }
  }
}
