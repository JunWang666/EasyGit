import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:git2dart/git2dart.dart' hide GitCredential;
import 'package:git2dart_binaries/git2dart_binaries.dart' as native;

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
    if (Platform.isMacOS) {
      // libgit2 ships its own OpenSSL, which does not use the system keychain.
      Libgit2.setSSLCertLocations(file: '/etc/ssl/cert.pem');
    }
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

  List<GitCredential>? _credentialOverride;
  // Kept for parity with the CLI backend; LFS itself is not ported yet.
  // ignore: unused_field
  List<GitCredential> _lfsCredentials = const [];

  @override
  set onLog(void Function(GitCommandLog log)? callback) {}

  @override
  set credentialOverride(List<GitCredential>? value) {
    _credentialOverride = value;
  }

  @override
  set lfsCredentials(List<GitCredential> value) {
    _lfsCredentials = value;
  }

  @override
  void cancel() {
    _remoteCancelled = true;
    for (final receive in _remoteReceives.toList()) {
      receive.close();
    }
    for (final isolate in _remoteIsolates.toList()) {
      isolate.kill();
    }
  }

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
    final statusEntries = _rawStatus();
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

  /// Status including untracked files, collected by libgit2 in one pass with
  /// the untracked flags enabled (its defaults omit them).
  Map<String, Set<GitStatus>> _rawStatus() {
    return using((arena) {
      final opts = arena<native.git_status_options>();
      native.libgit2Runtime.bindings.git_status_options_init(
          opts, native.GIT_STATUS_OPTIONS_VERSION);
      opts.ref.flags = native.git_status_opt_t.GIT_STATUS_OPT_INCLUDE_UNTRACKED.value |
          native.git_status_opt_t.GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.value;
      final out = arena<Pointer<native.git_status_list>>();
      // ignore: invalid_use_of_internal_member
      final error = native.libgit2Runtime.bindings.git_status_list_new(out, _repo.pointer, opts);
      if (error < 0) throw StateError('git_status_list_new failed: $error');
      final list = out.value;
      try {
        final result = <String, Set<GitStatus>>{};
        final count = native.libgit2Runtime.bindings.git_status_list_entrycount(list);
        for (var i = 0; i < count; i++) {
          final entry =
              native.libgit2Runtime.bindings.git_status_byindex(list, i);
          var delta = entry.ref.index_to_workdir;
          if (entry.ref.head_to_index != nullptr) {
            delta = entry.ref.head_to_index;
          }
          final path =
              (delta.ref.flags & native.git_delta_t.GIT_DELTA_RENAMED.value) != 0
                  ? delta.ref.new_file.path.cast<Utf8>().toDartString()
                  : delta.ref.old_file.path.cast<Utf8>().toDartString();
          result[path] = GitStatus.values
              .skip(1)
              .where((e) => (entry.ref.statusAsInt & e.value) != 0)
              .toSet();
        }
        return result;
      } finally {
        native.libgit2Runtime.bindings.git_status_list_free(list);
      }
    });
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
        // origin/HEAD is a symbolic ref with no direct target OID.
        if (!isLocal && branch.name.endsWith('/HEAD')) continue;
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
        in ['refs/heads/$rev', 'refs/remotes/$rev', 'refs/tags/$rev']) {
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
      throw GitException('git log', '$e');
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
      {bool amend = false, String? authorName, String? authorEmail}) async {
    final index = _repo.index;
    final head = Commit.lookup(repo: _repo, oid: _resolve('HEAD'));
    // Start from HEAD and apply only the selected files, matching
    // `git commit --only`: everything else in the working tree is left alone.
    index.readTree(head.tree);
    for (final change in files) {
      if (change.kind == ChangeKind.deleted) {
        index.remove(change.path);
      } else {
        index.add(change.path);
      }
    }
    final tree = Tree.lookup(repo: _repo, oid: index.writeTree());
    final signature = await _signature(authorName, authorEmail);
    final parents = amend
        ? [for (final parent in head.parents)
            Commit.lookup(repo: _repo, oid: parent)]
        : [head];
    Commit.create(
      repo: _repo,
      updateRef: 'HEAD',
      author: signature,
      committer: signature,
      message: message,
      tree: tree,
      parents: parents,
    );
    index.write();
  }

  Future<Signature> _signature(String? name, String? email) async {
    if (name != null && email != null) {
      return Signature.create(name: name, email: email);
    }
    final id = await identity();
    return Signature.create(
      name: name ?? id.name ?? 'EasyGit',
      email: email ?? id.email ?? 'easygit@localhost',
    );
  }

  @override
  Future<void> rollback(List<FileChange> files) async {
    for (final change in files) {
      if (change.isUntracked) {
        await deleteWorkingFile(change.path);
        continue;
      }
      try {
        final commit = Commit.lookup(repo: _repo, oid: _resolve('HEAD'));
        final blob = Blob.lookup(repo: _repo, oid: commit.tree[change.path].oid);
        if (blob.isBinary) {
          await _file(change.path).writeAsBytes(blob.contentBytes);
        } else {
          await _file(change.path).writeAsString(blob.content);
        }
      } catch (_) {
        // The file did not exist in HEAD, so rolling back removes it.
        await deleteWorkingFile(change.path);
      }
    }
  }

  @override
  Future<void> addToVcs(List<String> paths) async {
    final index = _repo.index;
    for (final path in paths) {
      index.add(path);
    }
    index.write();
  }

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
  Future<void> fetch({void Function(String)? onProgress}) async {
    for (final name in await remotes()) {
      await _runRemote(name, const [], false, true, onProgress);
    }
  }

  @override
  Future<void> pull({bool rebase = false, void Function(String)? onProgress}) async =>
      _unsupported('pull');

  @override
  Future<void> push({bool force = false, void Function(String)? onProgress}) async {
    final st = await status();
    final branch = st.branch;
    if (branch == null) {
      throw const GitException('git push', 'Cannot push: HEAD is detached.');
    }
    final upstream = st.upstream;
    final remoteName = upstream == null
        ? await _defaultRemoteName()
        : upstream.substring(0, upstream.indexOf('/'));
    final target = upstream == null ? branch : upstream.substring(remoteName.length + 1);
    await _pushRef(
      remoteName,
      'refs/heads/$branch:refs/heads/$target',
      force: force,
      onProgress: onProgress,
    );
    if (upstream == null) {
      Branch.lookup(repo: _repo, name: branch).setUpstream('$remoteName/$branch');
    }
  }

  @override
  Future<void> pushBranch(GitRef ref,
      {void Function(String)? onProgress}) async {
    final upstream = ref.upstream;
    final remoteName = upstream == null || !upstream.contains('/')
        ? await _defaultRemoteName()
        : upstream.substring(0, upstream.indexOf('/'));
    final target = upstream == null || !upstream.contains('/')
        ? ref.name
        : upstream.substring(upstream.indexOf('/') + 1);
    await _pushRef(remoteName, 'refs/heads/${ref.name}:refs/heads/$target',
        onProgress: onProgress);
    if (upstream == null) {
      Branch.lookup(repo: _repo, name: ref.name)
          .setUpstream('$remoteName/${ref.name}');
    }
  }

  Future<void> _pushRef(String remoteName, String refspec,
      {bool force = false, void Function(String)? onProgress}) async {
    await _runRemote(
        remoteName, [if (force) '+$refspec' else refspec], true, false, onProgress);
  }

  Future<String> _defaultRemoteName() async {
    final all = await remotes();
    if (all.isEmpty) {
      throw const GitException('git push', 'No remote is configured.');
    }
    return all.contains('origin') ? 'origin' : all.first;
  }

  final Set<Isolate> _remoteIsolates = {};
  final Set<ReceivePort> _remoteReceives = {};
  var _remoteCancelled = false;

  /// Runs one remote operation in a background isolate. libgit2 calls are
  /// synchronous, so doing them on the UI isolate would freeze the window for
  /// the whole network round trip. Progress text is forwarded to [onProgress].
  Future<void> _runRemote(String remoteName, List<String> refspecs, bool push,
      bool prune, void Function(String)? onProgress) async {
    _remoteCancelled = false;
    final receive = ReceivePort();
    final job = <String, Object?>{
      'sendPort': receive.sendPort,
      'root': root,
      'remoteName': remoteName,
      'refspecs': refspecs,
      'push': push,
      'prune': prune,
      'credentials': [
        for (final c in _credentialOverride ?? GitRunner.credentials)
          [c.server, c.username, c.password],
      ],
    };
    final isolate = await Isolate.spawn(_remoteEntry, job);
    _remoteIsolates.add(isolate);
    _remoteReceives.add(receive);
    try {
      await for (final message in receive) {
        if (message is! List || message.length != 2) continue;
        switch (message[0]) {
          case 'progress':
            onProgress?.call(message[1] as String);
          case 'done':
            return;
          case 'error':
            throw GitException(push ? 'git push' : 'git fetch', '${message[1]}');
        }
      }
      if (_remoteCancelled) {
        throw GitException(push ? 'git push' : 'git fetch', 'Cancelled by user.',
            GitException.cancelledCode);
      }
    } finally {
      _remoteIsolates.remove(isolate);
      _remoteReceives.remove(receive);
      receive.close();
      isolate.kill();
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(2)} MiB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(1)} KiB';
    return '$bytes B';
  }

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

/// Entry point of the background isolate used for remote operations.
void _remoteEntry(Map<String, Object?> job) {
  final send = job['sendPort'] as SendPort;
  void emit(String text) => send.send(['progress', text]);
  try {
    if (Platform.isMacOS) {
      Libgit2.setSSLCertLocations(file: '/etc/ssl/cert.pem');
    }
    final repo = Repository.open(job['root'] as String);
    final remote = Remote.lookup(repo: repo, name: job['remoteName'] as String);
    final callbacks = _workerCallbacks(remote.url, job['credentials'], emit);
    final refspecs = (job['refspecs'] as List).cast<String>();
    if (job['push'] as bool) {
      remote.push(refspecs: refspecs, callbacks: callbacks);
    } else {
      remote.fetch(prune: GitFetchPrune.prune, callbacks: callbacks);
    }
    send.send(['done', '']);
  } catch (e) {
    send.send(['error', '$e']);
  }
}

Callbacks _workerCallbacks(
    String url, Object? credentials, void Function(String) emit) {
  UserPass? credential;
  for (final c in (credentials as List).cast<List>()) {
    final server = c[0] as String;
    if (url.startsWith(server)) {
      credential = UserPass(username: c[1] as String, password: c[2] as String);
      break;
    }
  }
  final watch = Stopwatch()..start();
  var lastBytes = 0;
  var lastMillis = 0;
  return Callbacks(
    credentials: credential,
    sidebandProgress: (message, len, payload) => emit(message),
    transferProgress: (stats) {
      final total = stats.totalObjects;
      final received = stats.receivedObjects;
      final percent = total == 0 ? 0 : (received * 100) ~/ total;
      final bytes = stats.receivedBytes;
      final millis = watch.elapsedMilliseconds;
      var text = 'Receiving objects: $percent% ($received/$total)';
      if (bytes > 0) {
        final elapsed = millis - lastMillis;
        final speed =
            elapsed <= 0 ? 0 : ((bytes - lastBytes) * 1000) ~/ elapsed;
        text +=
            ', ${Libgit2Backend._formatBytes(bytes)} | ${Libgit2Backend._formatBytes(speed)}/s';
      }
      lastBytes = bytes;
      lastMillis = millis;
      emit(text);
    },
  );
}
