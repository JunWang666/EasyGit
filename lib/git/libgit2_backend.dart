import 'dart:io';

import 'package:git2dart/git2dart.dart' hide GitCredential;

import 'git_backend.dart';
import 'git_runner.dart';
import 'lfs.dart';
import 'models.dart';

/// A [GitBackend] that uses libgit2 through `dart:ffi` instead of spawning
/// the git command line, so it also works on iOS and in shell-less sandboxes.
///
/// Opening repositories, status, refs, log and file access are implemented;
/// the remaining operations raise [UnimplementedError] until they are ported.
/// The CLI backend ([GitRepository]) stays the default everywhere.
class Libgit2Backend implements GitBackend {
  Libgit2Backend._(this._repo)
      : root = _stripSlash(_repo.workdir),
        gitDir = _stripSlash(_repo.path);

  final Repository _repo;

  static String _stripSlash(String path) =>
      path.length > 1 && path.endsWith('/') ? path.substring(0, path.length - 1) : path;

  /// Opens the repository that contains [dir].
  static Future<Libgit2Backend> open(String dir) async {
    try {
      final gitDir = Repository.discover(startPath: dir);
      return Libgit2Backend._(Repository.open(gitDir));
    } catch (_) {
      throw GitException('git rev-parse', 'not a git repository: $dir', 128);
    }
  }

  @override
  final String root;
  @override
  final String gitDir;

  @override
  String get name =>
      root.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? root;

  @override
  set onLog(void Function(GitCommandLog log)? callback) {}

  @override
  set credentialOverride(List<GitCredential>? value) {}

  @override
  set lfsCredentials(List<GitCredential> value) {}

  @override
  void cancel() {}

  File _file(String path) => File('$root/$path');

  Never _unsupported(String operation) => throw UnimplementedError(
      '$operation is not implemented by the libgit2 backend yet');

  // ------------------------------------------------------------------ status

  static const _stagedFlags = {
    GitStatus.indexNew,
    GitStatus.indexModified,
    GitStatus.indexDeleted,
    GitStatus.indexRenamed,
    GitStatus.indexTypeChange,
  };
  static const _worktreeFlags = {
    GitStatus.wtNew,
    GitStatus.wtModified,
    GitStatus.wtDeleted,
    GitStatus.wtRenamed,
    GitStatus.wtTypeChange,
  };

  @override
  Future<RepoStatus> status() async {
    final statusEntries = await _statusWithUntracked();
    final changes = <FileChange>[];
    for (final entry in statusEntries.entries) {
      final flags = entry.value;
      if (flags.contains(GitStatus.ignored)) continue;
      changes.add(FileChange(
        path: entry.key,
        kind: _changeKind(flags),
        staged: flags.any(_stagedFlags.contains),
        unstaged: flags.any(_worktreeFlags.contains),
      ));
    }
    changes.sort((a, b) => a.path.compareTo(b.path));

    String? branch;
    String? headHash;
    String? upstream;
    var ahead = 0;
    var behind = 0;
    try {
      final head = _repo.head;
      headHash = head.target.sha;
      if (head.shorthand != 'HEAD') {
        branch = head.shorthand;
        try {
          final upstreamName =
              Branch.lookup(repo: _repo, name: branch).upstreamName;
          upstream = upstreamName.replaceFirst('refs/remotes/', '');
          final upstreamOid = Reference.nameToId(
              repo: _repo, refName: upstreamName);
          final counts = _repo.aheadBehind(
              local: head.target, upstream: upstreamOid);
          ahead = counts[0];
          behind = counts[1];
        } catch (_) {
          upstream = null;
        }
      }
    } catch (_) {
      // Unborn branch: no HEAD commit yet.
    }

    return RepoStatus(
      branch: branch,
      headHash: headHash,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      changes: changes,
      state: _repoState(),
    );
  }

  /// libgit2's default status options do not include untracked files, so the
  /// working tree is walked as well and new files are probed individually.
  Future<Map<String, Set<GitStatus>>> _statusWithUntracked() async {
    final map = Map<String, Set<GitStatus>>.of(_repo.status);
    await _collectUntracked(Directory(root), map);
    return map;
  }

  Future<void> _collectUntracked(
      Directory dir, Map<String, Set<GitStatus>> map) async {
    await for (final entity in dir.list(followLinks: false)) {
      final rel = entity.path.substring(root.length + 1).replaceAll('\\', '/');
      if (rel == '.git' || rel.startsWith('.git/')) continue;
      if (entity is Directory) {
        await _collectUntracked(entity, map);
      } else if (entity is File && !map.containsKey(rel)) {
        final flags = _repo.statusFile(rel);
        if (flags.contains(GitStatus.wtNew)) map[rel] = {GitStatus.wtNew};
      }
    }
  }

  ChangeKind _changeKind(Set<GitStatus> flags) {    if (flags.contains(GitStatus.conflicted)) return ChangeKind.conflicted;
    if (flags.contains(GitStatus.wtNew)) return ChangeKind.untracked;
    if (flags.contains(GitStatus.indexRenamed) ||
        flags.contains(GitStatus.wtRenamed)) {
      return ChangeKind.renamed;
    }
    if (flags.contains(GitStatus.indexTypeChange) ||
        flags.contains(GitStatus.wtTypeChange)) {
      return ChangeKind.typeChanged;
    }
    if (flags.contains(GitStatus.indexDeleted) ||
        flags.contains(GitStatus.wtDeleted)) {
      return ChangeKind.deleted;
    }
    if (flags.contains(GitStatus.indexNew)) return ChangeKind.added;
    return ChangeKind.modified;
  }

  RepoState _repoState() {
    bool exists(String name) => File('$gitDir/$name').existsSync();
    if (exists('MERGE_HEAD')) return RepoState.merging;
    if (Directory('$gitDir/rebase-merge').existsSync() ||
        Directory('$gitDir/rebase-apply').existsSync()) {
      return RepoState.rebasing;
    }
    if (exists('CHERRY_PICK_HEAD')) return RepoState.cherryPicking;
    if (exists('REVERT_HEAD')) return RepoState.reverting;
    return RepoState.normal;
  }

  // -------------------------------------------------------------------- refs

  @override
  Future<List<GitRef>> refs() async {
    final result = <GitRef>[];
    for (final type in [GitBranch.local, GitBranch.remote]) {
      for (final branch in Branch.list(repo: _repo, type: type)) {
        final isLocal = type == GitBranch.local;
        final fullName = isLocal
            ? 'refs/heads/${branch.name}'
            : 'refs/remotes/${branch.name}';
        String? upstream;
        var ahead = 0;
        var behind = 0;
        if (isLocal) {
          try {
            final upstreamName = branch.upstreamName;
            upstream = upstreamName.replaceFirst('refs/remotes/', '');
            final counts = _repo.aheadBehind(
                local: branch.target,
                upstream: Reference.nameToId(
                    repo: _repo, refName: upstreamName));
            ahead = counts[0];
            behind = counts[1];
          } catch (_) {
            upstream = null;
          }
        }
        String subject = '';
        DateTime? date;
        try {
          final commit = Commit.lookup(repo: _repo, oid: branch.target);
          subject = commit.summary;
          date = _commitDate(commit);
        } catch (_) {
          // Ref pointing at something that is not a commit.
        }
        result.add(GitRef(
          fullName: fullName,
          name: branch.name,
          hash: branch.target.sha,
          type: isLocal ? RefType.local : RefType.remote,
          upstream: upstream,
          ahead: ahead,
          behind: behind,
          isHead: branch.isHead,
          subject: subject,
          date: date,
        ));
      }
    }
    for (final tag in Tag.list(repo: _repo)) {
      final oid = Reference.nameToId(repo: _repo, refName: 'refs/tags/$tag');
      result.add(GitRef(
          fullName: 'refs/tags/$tag',
          name: tag,
          hash: oid.sha,
          type: RefType.tag));
    }
    return result;
  }

  @override
  Future<List<String>> remotes() async => Remote.list(_repo);

  @override
  Future<Map<String, String>> remoteUrls() async {
    return {
      for (final name in Remote.list(_repo))
        name: Remote.lookup(repo: _repo, name: name).url,
    };
  }

  // --------------------------------------------------------------------- log

  Oid _resolve(String rev) {
    if (rev == 'HEAD') return Reference.nameToId(repo: _repo, refName: 'HEAD');
    if (rev.startsWith('refs/')) {
      return Reference.nameToId(repo: _repo, refName: rev);
    }
    for (final candidate
        in ['refs/heads/\$rev', 'refs/remotes/\$rev', 'refs/tags/\$rev']) {
      try {
        return Reference.nameToId(repo: _repo, refName: candidate);
      } catch (_) {
        // Not a ref with this name; try the next candidate.
      }
    }
    return Oid.fromSHA(_repo, rev);
  }

  static DateTime _commitDate(Commit commit) =>
      DateTime.fromMillisecondsSinceEpoch(commit.time * 1000, isUtc: true)
          .toLocal();

  @override
  Future<List<CommitInfo>> log({String? branch, int limit = 5000}) async {
    final labels = <String, List<RefLabel>>{};
    for (final ref in await refs()) {
      final label = switch (ref.type) {
        RefType.local => RefLabel(ref.name, RefLabelType.local,
            isCurrent: ref.isHead),
        RefType.remote => RefLabel(ref.name, RefLabelType.remote),
        RefType.tag => RefLabel(ref.name, RefLabelType.tag),
      };
      labels.putIfAbsent(ref.hash, () => []).add(label);
    }

    try {
      final start = _resolve(branch ?? 'HEAD');
      return _repo.log(oid: start).take(limit).map((commit) {
        return CommitInfo(
          hash: commit.oid.sha,
          parents: [for (final parent in commit.parents) parent.sha],
          author: commit.author.name,
          email: commit.author.email,
          date: _commitDate(commit),
          subject: commit.summary,
          refs: labels[commit.oid.sha] ?? const [],
        );
      }).toList();
    } catch (e) {
      throw GitException('git log', '\$e');
    }
  }

  @override
  Future<String> lastCommitMessage() async =>
      Commit.lookup(repo: _repo, oid: _resolve('HEAD')).message.trim();

  @override
  Future<String?> fileAt(String rev, String path) async {
    try {
      final commit = Commit.lookup(repo: _repo, oid: _resolve(rev));
      final entry = commit.tree[path];
      final blob = Blob.lookup(repo: _repo, oid: entry.oid);
      return blob.isBinary ? null : blob.content;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------- working files

  @override
  Future<String?> readWorkingFile(String path) async {
    try {
      return await _file(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<int?> workingFileSize(String path) async {
    try {
      return await _file(path).length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> writeWorkingFile(String path, String content) =>
      _file(path).writeAsString(content);

  @override
  Future<void> deleteWorkingFile(String path) => _file(path).delete();

  // ------------------------------------------------------- not yet ported

  @override
  Future<CommitDetails> commitDetails(String hash) async =>
      _unsupported('commitDetails');

  @override
  Future<void> commit(String message, List<FileChange> files,
          {bool amend = false, String? authorName, String? authorEmail}) async =>
      _unsupported('commit');

  @override
  Future<void> rollback(List<FileChange> files) async =>
      _unsupported('rollback');

  @override
  Future<void> addToVcs(List<String> paths) async => _unsupported('addToVcs');

  @override
  Future<void> stash(String message) async => _unsupported('stash');

  @override
  Future<void> stashPop([String? ref]) async => _unsupported('stashPop');

  @override
  Future<void> stashApply(String ref) async => _unsupported('stashApply');

  @override
  Future<void> stashDrop(String ref) async => _unsupported('stashDrop');

  @override
  /// Stashes are not listed yet; an empty list keeps the sidebar usable.
  Future<List<StashEntry>> stashes() async => const [];

  @override
  /// Worktrees are not listed yet; an empty list keeps the sidebar usable.
  Future<List<WorktreeInfo>> worktrees() async => const [];

  @override
  Future<void> addWorktree(String path, String commitish,
          {String? newBranch}) async =>
      _unsupported('addWorktree');

  @override
  Future<void> removeWorktree(String path, {bool force = false}) async =>
      _unsupported('removeWorktree');

  @override
  Future<void> pruneWorktrees() async => _unsupported('pruneWorktrees');

  @override
  Future<void> fetch({void Function(String)? onProgress}) async =>
      _unsupported('fetch');

  @override
  Future<void> pull({bool rebase = false, void Function(String)? onProgress}) async =>
      _unsupported('pull');

  @override
  Future<void> push({bool force = false, void Function(String)? onProgress}) async =>
      _unsupported('push');

  @override
  Future<void> pushBranch(GitRef ref,
          {void Function(String)? onProgress}) async =>
      _unsupported('pushBranch');

  @override
  Future<RepoIdentity> identity() async {
    final local = Config.open('$gitDir/config');
    final global = Config.global();
    return RepoIdentity(
      localName: _readConfig(local, 'user.name'),
      localEmail: _readConfig(local, 'user.email'),
      globalName: _readConfig(global, 'user.name'),
      globalEmail: _readConfig(global, 'user.email'),
    );
  }

  String? _readConfig(Config config, String key) {
    try {
      final value = config.getString(key);
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setLocalIdentity(String? name, String? email) async {
    final config = Config.open('$gitDir/config');
    _writeConfig(config, 'user.name', name);
    _writeConfig(config, 'user.email', email);
  }

  void _writeConfig(Config config, String key, String? value) {
    if (value == null || value.isEmpty) {
      try {
        config.delete(key);
      } catch (_) {
        // Was not set.
      }
    } else {
      config[key] = value;
    }
  }

  @override
  Future<String?> accountId() async =>
      _readConfig(Config.open('$gitDir/config'), 'easygit.account');

  @override
  Future<void> setAccountId(String? id) async =>
      _writeConfig(Config.open('$gitDir/config'), 'easygit.account', id);

  @override
  Future<void> checkout(String ref) async => _unsupported('checkout');

  @override
  Future<void> checkoutRevision(String rev) async =>
      _unsupported('checkoutRevision');

  @override
  Future<void> checkoutRemote(GitRef remote, List<GitRef> all) async =>
      _unsupported('checkoutRemote');

  @override
  Future<void> createBranch(String name, String startPoint,
          {required bool checkout}) async =>
      _unsupported('createBranch');

  @override
  Future<void> renameBranch(String from, String to) async =>
      _unsupported('renameBranch');

  @override
  Future<void> deleteBranch(GitRef ref, {bool force = false}) async =>
      _unsupported('deleteBranch');

  @override
  Future<void> merge(String ref) async => _unsupported('merge');

  @override
  Future<void> rebase(String onto) async => _unsupported('rebase');

  @override
  Future<void> abortOperation(RepoState state) async =>
      _unsupported('abortOperation');

  @override
  Future<void> continueOperation(RepoState state) async =>
      _unsupported('continueOperation');

  @override
  Future<void> cherryPick(String hash) async => _unsupported('cherryPick');

  @override
  Future<void> revert(String hash) async => _unsupported('revert');

  @override
  Future<void> reset(String hash, ResetMode mode) async =>
      _unsupported('reset');

  @override
  Future<void> createTag(String name, String hash) async =>
      _unsupported('createTag');

  @override
  /// LFS is not implemented by this backend yet, so repositories are treated
  /// as non-LFS instead of failing the whole status refresh.
  Future<bool> usesLfs() async => false;

  @override
  Future<List<String>> lfsPatterns() async => const [];

  @override
  Future<bool> lfsHooksInstalled() async => false;

  @override
  Future<void> lfsInstallHooks() async => _unsupported('lfsInstallHooks');

  @override
  Future<List<LfsFile>> lfsFiles() async => const [];

  @override
  Future<LfsEnv> lfsEnv() async => _unsupported('lfsEnv');

  @override
  Future<Set<String>> lfsTrackedPaths(Iterable<String> paths) async =>
      _unsupported('lfsTrackedPaths');

  @override
  Future<void> lfsTrack(List<String> patterns) async =>
      _unsupported('lfsTrack');

  @override
  Future<void> lfsPull([List<String>? paths,
          void Function(String)? onProgress]) async =>
      _unsupported('lfsPull');

  @override
  Future<void> lfsPush(String remote, List<String> oids,
          {void Function(String)? onProgress}) async =>
      _unsupported('lfsPush');

  @override
  Future<LfsCleanResult> lfsClean(List<LfsFile> files,
          {Set<String> changedPaths = const {}}) async =>
      _unsupported('lfsClean');

  @override
  Future<void> lfsFetch(String remote, String rev, String path,
          {void Function(String)? onProgress}) async =>
      _unsupported('lfsFetch');

  @override
  Future<LfsServerConfig> lfsServerConfig() async =>
      _unsupported('lfsServerConfig');

  @override
  Future<void> setLfsServer(LfsUrlSource source, String url) async =>
      _unsupported('setLfsServer');

  @override
  Future<void> addRemote(String name, String url) async =>
      _unsupported('addRemote');

  @override
  Future<void> setRemoteUrl(String name, String url) async =>
      _unsupported('setRemoteUrl');

  @override
  Future<void> renameRemote(String from, String to) async =>
      _unsupported('renameRemote');

  @override
  Future<void> removeRemote(String name) async => _unsupported('removeRemote');

  @override
  Future<String?> remoteDefaultBranch(String remote) async =>
      _unsupported('remoteDefaultBranch');
}
