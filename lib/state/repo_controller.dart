import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:url_launcher/url_launcher.dart';

import '../git/git_repository.dart';
import '../git/graph.dart';
import '../git/lfs.dart';
import '../git/models.dart';
import '../hosting/hosting.dart';
import '../net/network.dart';
import 'accounts_store.dart';

class DiffContent {
  const DiffContent(this.left, this.right, {this.lfs});

  final String? left;
  final String? right;

  /// Set for files stored with Git LFS: shown as a size/preview card.
  final LfsDiff? lfs;
}

/// One version of an LFS-managed file in a diff.
class LfsSide {
  const LfsSide({this.pointer, required this.size, this.localPath, this.download});

  final LfsPointer? pointer;
  final int size;

  /// A local file with the real content, when available.
  final String? localPath;

  /// Fetches this version when it is not available locally.
  final Future<void> Function()? download;

  bool get available => localPath != null;
}

class LfsDiff {
  const LfsDiff(this.left, this.right);

  final LfsSide? left;
  final LfsSide? right;
}

/// Git LFS state of a repository.
class LfsState {
  /// git-lfs version line, or null when git-lfs is not installed.
  String? version;
  bool usesLfs = false;
  bool hooksInstalled = true;
  List<String> patterns = const [];
  Map<String, LfsFile> files = const {};

  /// Changed paths that .gitattributes routes through LFS.
  Set<String> trackedChanges = const {};
  LfsEnv env = const LfsEnv();

  bool get installed => version != null;
  bool get needsSetup => usesLfs && (!installed || !hooksInstalled);
  String? get endpoint => env.endpoint;

  /// Files whose real content is not in the working tree.
  List<LfsFile> get missing => [
        for (final f in files.values)
          if (!f.checkedOut) f
      ];

  bool isTracked(String path) => trackedChanges.contains(path) || files.containsKey(path);
}

/// The tabs of the main area for a repository.
enum RepoView {
  changes('Local Changes'),
  history('History'),
  branches('Branches'),
  stashes('Stashes'),
  worktrees('Worktrees');

  const RepoView(this.label);

  final String label;
}

/// A file diff shown inline in the Local Changes or History view.
class DiffTab {
  DiffTab({
    required this.id,
    required this.change,
    required this.leftTitle,
    required this.rightTitle,
    required this.loader,
  });

  final String id;
  final FileChange change;
  final String leftTitle;
  final String rightTitle;
  final Future<DiffContent> Function() loader;

  int version = 0;
  Future<DiffContent>? _content;

  Future<DiffContent> get content => _content ??= loader();
  bool get isWorkingTree => id.startsWith('wt:');

  void reload() {
    _content = null;
    version++;
  }
}

enum NotificationAction { networkSettings, accounts }

class AppNotification {
  AppNotification(this.id, this.title, this.message,
      {this.isError = false, this.hint, this.action});

  final int id;
  final String title;
  final String message;
  final bool isError;

  /// A plain-language explanation shown above the raw error.
  final String? hint;
  final NotificationAction? action;
}

/// State of an open repository, shared by every panel of the workspace.
class RepoController extends ChangeNotifier {
  RepoController(this.repo, this.accounts) {
    repo.onLog = _addLog;
    accounts.addListener(_applyAccount);
    repo.accountId().then((id) {
      accountId = id;
      _applyAccount();
    });
  }

  final GitRepository repo;
  final AccountsStore accounts;

  /// The account this repository fetches and pushes with, or null to pick
  /// the account by server (see `GitRepository.accountId`).
  String? accountId;

  HostingAccount? get account => accounts.accounts.where((a) => a.id == accountId).firstOrNull;

  void _applyAccount() {
    final a = account;
    repo.credentialOverride = a == null ? null : accounts.credentialsPreferring(a);
  }

  Future<void> setAccount(String? id) async {
    await repo.setAccountId(id);
    accountId = id;
    _applyAccount();
    notifyListeners();
  }

  RepoStatus? status;
  List<GitRef> refs = const [];
  List<String> remotes = const [];
  Map<String, String> remoteUrls = const {};
  List<CommitInfo> commits = const [];
  List<GraphRow> graph = const [];
  bool logLoading = false;

  // Log filters.
  String? branchFilter;
  String textFilter = '';
  String? authorFilter;
  List<int> _visible = const [];

  // Selection in the log.
  String? selectedHash;
  CommitDetails? details;
  int _detailsToken = 0;
  int revealTick = 0;

  // Commit tool window.
  final Set<String> included = {};
  Set<String> _knownChanges = {};
  final messageController = TextEditingController();
  final messageFocus = FocusNode();
  bool amend = false;

  List<StashEntry> stashes = const [];
  List<WorktreeInfo> worktrees = const [];
  final LfsState lfs = LfsState();

  RepoView view = RepoView.changes;
  DiffTab? changesDiff;
  DiffTab? historyDiff;

  String? busy;
  final List<GitCommandLog> consoleLog = [];
  final List<AppNotification> notifications = [];
  var _notificationId = 0;
  Future<void>? _refresh;
  bool _refreshQueued = false;
  bool _disposed = false;

  String get name => repo.name;
  List<int> get visible => _visible;
  bool get graphVisible => textFilter.trim().isEmpty && authorFilter == null;

  List<GitRef> get localBranches => refs.where((r) => r.type == RefType.local).toList();
  List<GitRef> get remoteBranches => refs.where((r) => r.type == RefType.remote).toList();
  List<GitRef> get tags => refs.where((r) => r.type == RefType.tag).toList();
  String get currentBranchLabel => status?.headLabel ?? '';

  List<FileChange> get trackedChanges =>
      status?.changes.where((c) => !c.isUntracked).toList() ?? const [];
  List<FileChange> get untrackedChanges =>
      status?.changes.where((c) => c.isUntracked).toList() ?? const [];

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    accounts.removeListener(_applyAccount);
    messageController.dispose();
    messageFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- refresh

  /// Reloads status, refs and log. Calls made while a refresh is running
  /// queue one more pass and complete when that pass is done.
  Future<void> refreshAll() {
    final running = _refresh;
    if (running != null) {
      _refreshQueued = true;
      return running;
    }
    return _refresh = _runRefresh();
  }

  Future<void> _runRefresh() async {
    try {
      do {
        _refreshQueued = false;
        await Future.wait([refreshStatus(), _refreshRefs()]);
        await refreshLog();
      } while (_refreshQueued && !_disposed);
    } finally {
      _refresh = null;
    }
  }

  /// Status and refs only, for repositories that are not on screen.
  Future<void> refreshSummary() => Future.wait([refreshStatus(), _refreshRefs()]);

  Future<void> refreshStatus() async {
    try {
      status = await repo.status();
      _syncIncluded();
      // Which changed files go to LFS (also new files not committed yet).
      lfs.trackedChanges = await repo.usesLfs()
          ? await repo.lfsTrackedPaths(status!.changes.map((c) => c.path))
          : const {};
      final diff = changesDiff;
      if (diff != null) {
        final current = status!.changes.where((c) => c.path == diff.change.path).firstOrNull;
        if (current == null) {
          changesDiff = null;
        } else if (current.kind != diff.change.kind) {
          changesDiff = null;
          openWorkingDiff(current);
        } else {
          diff.reload();
        }
      }
      if (changesDiff == null && status!.changes.isNotEmpty) {
        openWorkingDiff(trackedChanges.firstOrNull ?? status!.changes.first);
      }
      notifyListeners();
    } on GitException catch (e) {
      _notify('Cannot read repository status', e.message, isError: true);
    }
  }

  Future<void> _refreshRefs() async {
    try {
      refs = await repo.refs();
      remoteUrls = await repo.remoteUrls();
      remotes = remoteUrls.keys.toList();
      stashes = await repo.stashes();
      worktrees = await repo.worktrees();
      await _refreshLfs();
      notifyListeners();
    } on GitException catch (e) {
      _notify('Cannot read branches', e.message, isError: true);
    }
  }

  Future<void> refreshLog() async {
    logLoading = true;
    notifyListeners();
    try {
      commits = await repo.log(branch: branchFilter);
      graph = buildGraph(commits);
      _recomputeVisible();
      final selected = selectedHash;
      if (selected != null &&
          !commits.any((c) => c.hash == selected) &&
          !stashes.any((s) => s.hash == selected)) {
        selectedHash = null;
        details = null;
        historyDiff = null;
      }
    } on GitException catch (e) {
      commits = const [];
      graph = const [];
      _recomputeVisible();
      _notify('Cannot load log', e.message, isError: true);
    } finally {
      logLoading = false;
      notifyListeners();
    }
  }

  void _syncIncluded() {
    final changes = status?.changes ?? const [];
    final paths = {for (final c in changes) c.path};
    included.removeWhere((p) => !paths.contains(p));
    // Newly appearing tracked changes are included by default, like the IDE.
    for (final c in changes) {
      if (!_knownChanges.contains(c.path) && !c.isUntracked) included.add(c.path);
    }
    _knownChanges = paths;
  }

  // ---------------------------------------------------------------- log filters

  void setTextFilter(String value) {
    textFilter = value;
    _recomputeVisible();
    notifyListeners();
  }

  void setAuthorFilter(String? author) {
    authorFilter = author;
    _recomputeVisible();
    notifyListeners();
  }

  Future<void> setBranchFilter(String? branch) async {
    if (branch == branchFilter) return;
    branchFilter = branch;
    await refreshLog();
  }

  void _recomputeVisible() {
    final q = textFilter.trim().toLowerCase();
    if (q.isEmpty && authorFilter == null) {
      _visible = List.generate(commits.length, (i) => i);
      return;
    }
    _visible = [
      for (var i = 0; i < commits.length; i++)
        if (_matches(commits[i], q)) i,
    ];
  }

  bool _matches(CommitInfo c, String q) {
    if (authorFilter != null && c.author != authorFilter) return false;
    if (q.isEmpty) return true;
    return c.subject.toLowerCase().contains(q) ||
        c.hash.startsWith(q) ||
        c.author.toLowerCase().contains(q);
  }

  List<String> get authors {
    final counts = <String, int>{};
    for (final c in commits) {
      counts[c.author] = (counts[c.author] ?? 0) + 1;
    }
    final list = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list;
  }

  // ---------------------------------------------------------------- selection

  Future<void> selectCommit(String? hash) async {
    if (hash == selectedHash) return;
    selectedHash = hash;
    details = null;
    historyDiff = null;
    notifyListeners();
    if (hash == null) return;
    final token = ++_detailsToken;
    try {
      final d = await repo.commitDetails(hash);
      if (token == _detailsToken) {
        details = d;
        // Show the first changed file right away.
        if (d.files.isNotEmpty) openCommitDiff(d.info, d.files.first);
        notifyListeners();
      }
    } on GitException catch (e) {
      if (token == _detailsToken) _notify('Cannot load commit', e.message, isError: true);
    }
  }

  /// Selects [hash] and asks the log to scroll it into view.
  void reveal(String hash) {
    if (!commits.any((c) => c.hash == hash) && branchFilter != null) {
      branchFilter = null;
      refreshLog().then((_) => reveal(hash));
      return;
    }
    selectCommit(hash);
    revealTick++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- notifications

  void _addLog(GitCommandLog log) {
    consoleLog.add(log);
    if (consoleLog.length > 500) consoleLog.removeAt(0);
    notifyListeners();
  }

  void _notify(String title, String message, {bool isError = false}) {
    // Explain network failures and offer the setting that fixes them.
    final hint = isError ? networkHint(message) : null;
    final action = hint == null
        ? null
        : (hint.contains('Accounts')
            ? NotificationAction.accounts
            : NotificationAction.networkSettings);
    final n = AppNotification(++_notificationId, title, message,
        isError: isError, hint: hint, action: action);
    notifications.add(n);
    if (notifications.length > 4) notifications.removeAt(0);
    notifyListeners();
    Timer(
        Duration(seconds: isError ? (hint != null ? 20 : 12) : 5), () => dismissNotification(n.id));
  }

  void dismissNotification(int id) {
    notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  /// Runs a user-visible git operation, reporting failure as a notification.
  Future<bool> run(String title, Future<void> Function() action, {String? success}) async {
    if (busy != null) {
      _notify(title, 'Another operation is in progress: $busy', isError: true);
      return false;
    }
    busy = title;
    notifyListeners();
    try {
      await action();
      if (success != null) _notify(success, '');
      return true;
    } on GitException catch (e) {
      _notify('$title failed', e.message, isError: true);
      return false;
    } finally {
      busy = null;
      notifyListeners();
      await refreshAll();
    }
  }

  // ---------------------------------------------------------------- commit

  void toggleIncluded(String path, bool value) {
    value ? included.add(path) : included.remove(path);
    notifyListeners();
  }

  void setIncluded(Iterable<FileChange> changes, bool value) {
    for (final c in changes) {
      value ? included.add(c.path) : included.remove(c.path);
    }
    notifyListeners();
  }

  Future<void> setAmend(bool value) async {
    amend = value;
    notifyListeners();
    if (value && messageController.text.trim().isEmpty) {
      try {
        messageController.text = await repo.lastCommitMessage();
      } on GitException {
        // No previous commit to amend.
      }
    }
  }

  Future<void> commit({bool andPush = false}) async {
    final message = messageController.text.trim();
    final files = status?.changes.where((c) => included.contains(c.path)).toList() ?? [];
    if (message.isEmpty) {
      _notify('Commit', 'Please enter a commit message.', isError: true);
      messageFocus.requestFocus();
      return;
    }
    if (files.isEmpty && !amend) {
      _notify('Commit', 'No files are selected to commit.', isError: true);
      return;
    }
    final firstLine = message.split('\n').first;
    final ok = await run(
      andPush ? 'Committing and pushing' : 'Committing',
      () async {
        await repo.commit(message, files, amend: amend);
        if (andPush) await repo.push();
      },
      success: andPush
          ? 'Committed and pushed: $firstLine'
          : '${files.length} file${files.length == 1 ? '' : 's'} committed: $firstLine',
    );
    if (ok) {
      messageController.clear();
      amend = false;
      notifyListeners();
    }
  }

  Future<void> rollback(List<FileChange> files) => run('Rollback', () => repo.rollback(files),
      success: '${files.length} file${files.length == 1 ? '' : 's'} rolled back');

  Future<void> addToVcs(List<FileChange> files) async {
    final ok = await run('Add to VCS', () => repo.addToVcs([for (final f in files) f.path]));
    if (ok) {
      included.addAll(files.map((f) => f.path));
      notifyListeners();
    }
  }

  Future<void> stash(String message) =>
      run('Stash', () => repo.stash(message), success: 'Changes stashed');

  Future<void> stashPop() => run('Unstash', () => repo.stashPop(), success: 'Stash applied');

  // ---------------------------------------------------------------- remote

  Future<void> fetch() => run('Fetching', repo.fetch, success: 'Fetch finished');

  Future<void> pull({bool rebase = false}) =>
      run('Updating project', () => repo.pull(rebase: rebase), success: 'Project updated');

  Future<void> push({bool force = false}) =>
      run('Pushing', () => repo.push(force: force), success: 'Pushed $currentBranchLabel');

  Future<void> pushBranch(GitRef ref) =>
      run('Pushing ${ref.name}', () => repo.pushBranch(ref), success: 'Pushed ${ref.name}');

  // ---------------------------------------------------------------- branches

  Future<void> checkout(GitRef ref) {
    if (ref.type == RefType.remote) {
      return run('Checking out ${ref.name}', () => repo.checkoutRemote(ref, refs),
          success: 'Checked out ${ref.branchName}');
    }
    if (ref.type == RefType.tag) {
      return run('Checking out ${ref.name}', () => repo.checkoutRevision(ref.name),
          success: 'Checked out tag ${ref.name}');
    }
    return run('Checking out ${ref.name}', () => repo.checkout(ref.name),
        success: 'Checked out ${ref.name}');
  }

  Future<void> checkoutRevision(String rev) =>
      run('Checking out $rev', () => repo.checkoutRevision(rev), success: 'Checked out $rev');

  Future<void> createBranch(String name, String startPoint, {required bool checkout}) =>
      run('Creating branch $name', () => repo.createBranch(name, startPoint, checkout: checkout),
          success: 'Branch $name created');

  Future<void> renameBranch(GitRef ref, String newName) =>
      run('Renaming ${ref.name}', () => repo.renameBranch(ref.name, newName),
          success: 'Branch renamed to $newName');

  Future<void> deleteRef(GitRef ref, {bool force = false}) =>
      run('Deleting ${ref.name}', () => repo.deleteBranch(ref, force: force),
          success: 'Deleted ${ref.name}');

  Future<void> merge(String ref) =>
      run('Merging $ref', () => repo.merge(ref), success: 'Merged $ref into $currentBranchLabel');

  Future<void> rebase(String onto) => run('Rebasing onto $onto', () => repo.rebase(onto),
      success: 'Rebased $currentBranchLabel onto $onto');

  Future<void> abortOperation() {
    final state = status?.state ?? RepoState.normal;
    return run('Abort', () => repo.abortOperation(state), success: 'Aborted');
  }

  Future<void> continueOperation() {
    final state = status?.state ?? RepoState.normal;
    return run('Continue', () => repo.continueOperation(state), success: 'Continued');
  }

  // ---------------------------------------------------------------- commits

  Future<void> cherryPick(CommitInfo c) =>
      run('Cherry-pick', () => repo.cherryPick(c.hash), success: 'Cherry-picked ${c.shortHash}');

  Future<void> revert(CommitInfo c) =>
      run('Revert', () => repo.revert(c.hash), success: 'Reverted ${c.shortHash}');

  Future<void> reset(CommitInfo c, ResetMode mode) => run('Reset', () => repo.reset(c.hash, mode),
      success: '$currentBranchLabel reset to ${c.shortHash}');

  Future<void> createTag(String name, CommitInfo c) =>
      run('Creating tag', () => repo.createTag(name, c.hash), success: 'Tag $name created');

  // ---------------------------------------------------------------- hosting

  /// The remote the current branch tracks, else `origin`, else the first one.
  String? get primaryRemote {
    final upstream = status?.upstream;
    if (upstream != null && upstream.contains('/')) {
      final name = upstream.substring(0, upstream.indexOf('/'));
      if (remoteUrls.containsKey(name)) return name;
    }
    if (remoteUrls.containsKey('origin')) return 'origin';
    return remoteUrls.keys.firstOrNull;
  }

  /// Web links for [remote] (default: [primaryRemote]) if it is on a known host.
  RepoWeb? webFor([String? remote]) {
    final name = remote ?? primaryRemote;
    final url = name == null ? null : remoteUrls[name];
    return url == null ? null : RepoWeb.forRemote(url, accounts.accounts);
  }

  /// Shows an error notification for work done outside this controller.
  void reportError(String title, String message) => _notify(title, message, isError: true);

  Future<void> openUrl(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        _notify('Cannot open browser', url, isError: true);
      }
    } catch (e) {
      _notify('Cannot open browser', '$e', isError: true);
    }
  }

  /// Pushes [branch] if it has no upstream yet, then opens the hosting
  /// service's "new pull/merge request" page for it.
  Future<void> createRequest(GitRef branch) async {
    var ref = branch;
    if (ref.upstream == null) {
      final ok = await run('Pushing ${ref.name}', () => repo.pushBranch(ref));
      if (!ok) return;
      ref = refs.firstWhere((r) => r.fullName == branch.fullName, orElse: () => branch);
    }
    final upstream = ref.upstream;
    final remote = upstream != null && upstream.contains('/')
        ? upstream.substring(0, upstream.indexOf('/'))
        : primaryRemote;
    final web = webFor(remote);
    if (web == null || remote == null) {
      _notify('Create ${web?.kind.requestName ?? 'Pull Request'}',
          'The remote is not on GitHub, GitLab or Gitea.',
          isError: true);
      return;
    }
    final remoteBranch = upstream != null && upstream.contains('/')
        ? upstream.substring(upstream.indexOf('/') + 1)
        : ref.name;
    final base = await repo.remoteDefaultBranch(remote);
    await openUrl(web.newRequest(remoteBranch, base: base == remoteBranch ? null : base));
  }

  Future<void> addRemote(String name, String url) =>
      run('Adding remote $name', () => repo.addRemote(name, url), success: 'Remote $name added');

  Future<void> editRemote(String oldName, String name, String url) => run(
        'Updating remote $oldName',
        () async {
          if (name != oldName) await repo.renameRemote(oldName, name);
          if (url != remoteUrls[oldName]) await repo.setRemoteUrl(name, url);
        },
        success: 'Remote $name updated',
      );

  Future<void> removeRemote(String name) =>
      run('Removing remote $name', () => repo.removeRemote(name), success: 'Remote $name removed');

  // ---------------------------------------------------------------- stashes & worktrees

  Future<void> applyStash(StashEntry s, {bool pop = false}) => run(
      pop ? 'Unstash' : 'Apply stash', () => pop ? repo.stashPop(s.ref) : repo.stashApply(s.ref),
      success: pop ? 'Popped ${s.ref}' : 'Applied ${s.ref}');

  Future<void> dropStash(StashEntry s) =>
      run('Drop stash', () => repo.stashDrop(s.ref), success: 'Dropped ${s.ref}');

  /// Selects a stash so its files and diff show in the Stashes view.
  void showStash(StashEntry s) {
    setView(RepoView.stashes);
    selectCommit(s.hash);
  }

  Future<bool> addWorktree(String path, String commitish, {String? newBranch}) =>
      run('Adding worktree', () => repo.addWorktree(path, commitish, newBranch: newBranch),
          success: 'Worktree created at $path');

  Future<void> removeWorktree(WorktreeInfo w, {bool force = false}) =>
      run('Removing worktree', () => repo.removeWorktree(w.path, force: force),
          success: 'Worktree ${w.name} removed');

  Future<void> pruneWorktrees() =>
      run('Pruning worktrees', repo.pruneWorktrees, success: 'Stale worktrees pruned');

  // ---------------------------------------------------------------- Git LFS

  Future<void> _refreshLfs() async {
    lfs.version = await GitRepository.lfsVersion();
    lfs.usesLfs = await repo.usesLfs();
    if (!lfs.usesLfs || !lfs.installed) {
      lfs
        ..files = const {}
        ..patterns = await repo.lfsPatterns()
        ..hooksInstalled = true;
      return;
    }
    final files = await repo.lfsFiles();
    lfs
      ..files = {for (final f in files) f.path: f}
      ..env = await repo.lfsEnv()
      ..hooksInstalled = await repo.lfsHooksInstalled()
      ..patterns = await repo.lfsPatterns();
  }

  Future<void> lfsInstallHooks() => run('Setting up Git LFS', repo.lfsInstallHooks,
      success: 'Git LFS is set up for this repository');

  /// Downloads LFS content into the working tree ([paths] or everything).
  Future<void> lfsDownload([List<String>? paths]) =>
      run('Downloading LFS files', () => repo.lfsPull(paths),
          success: paths == null || paths.length != 1
              ? 'LFS files downloaded'
              : 'Downloaded ${paths.first}');

  Future<bool> lfsTrack(List<String> patterns) =>
      run('Tracking with LFS', () => repo.lfsTrack(patterns),
          success: 'LFS now manages ${patterns.join(', ')}');

  Future<void> setLfsServer(LfsUrlSource source, String url) =>
      run('Changing LFS server', () => repo.setLfsServer(source, url),
          success: source == LfsUrlSource.shared
              ? 'LFS server saved in .lfsconfig. Commit it to share with the team.'
              : 'LFS server updated');

  LfsSide? _lfsSideFromPointer(String? text, {Future<void> Function()? download}) {
    final pointer = LfsPointer.parse(text);
    if (pointer == null) return null;
    final path = lfs.env.objectPath(pointer.oid);
    final available = path != null && File(path).existsSync();
    return LfsSide(
      pointer: pointer,
      size: pointer.size,
      localPath: available ? path : null,
      download: available ? null : download,
    );
  }

  Future<LfsSide?> _lfsSideFromWorkingFile(String relPath) async {
    final file = File('${repo.root}/$relPath');
    if (!await file.exists()) return null;
    final length = await file.length();
    // A pointer in the working tree means the content was never downloaded.
    if (length < 1024) {
      final side = _lfsSideFromPointer(await file.readAsString().catchError((_) => ''),
          download: () => lfsDownload([relPath]));
      if (side != null) return side;
    }
    return LfsSide(size: length, localPath: file.path);
  }

  // ---------------------------------------------------------------- views & diffs

  void setView(RepoView value) {
    if (view == value) return;
    view = value;
    notifyListeners();
  }

  /// Shows the working-tree diff of [change] in the Local Changes view.
  void openWorkingDiff(FileChange change) {
    if (changesDiff?.id == 'wt:${change.path}') return;
    changesDiff = DiffTab(
      id: 'wt:${change.path}',
      change: change,
      leftTitle: 'HEAD',
      rightTitle: 'Working tree',
      loader: () async {
        final noBase = change.kind == ChangeKind.added ||
            change.kind == ChangeKind.untracked ||
            !(status?.hasCommits ?? false);
        final left = noBase ? null : await repo.fileAt('HEAD', change.oldPath ?? change.path);
        final deleted = change.kind == ChangeKind.deleted;
        // LFS files: compare sizes and previews instead of pointer text.
        if (lfs.isTracked(change.path) || LfsPointer.parse(left) != null) {
          final remote = primaryRemote ?? 'origin';
          return DiffContent(null, null,
              lfs: LfsDiff(
                _lfsSideFromPointer(left,
                    download: () =>
                        _lfsFetchVersion(remote, 'HEAD', change.oldPath ?? change.path)),
                deleted ? null : await _lfsSideFromWorkingFile(change.path),
              ));
        }
        final right = deleted ? null : await repo.readWorkingFile(change.path);
        return DiffContent(left, right);
      },
    );
    notifyListeners();
  }

  Future<void> _lfsFetchVersion(String remote, String rev, String path) async {
    await run('Downloading LFS object', () => repo.lfsFetch(remote, rev, path));
    changesDiff?.reload();
    historyDiff?.reload();
    notifyListeners();
  }

  /// Shows [change] of [commit] (against its first parent) in the History view.
  void openCommitDiff(CommitInfo commit, FileChange change) {
    final parent = commit.parents.firstOrNull;
    if (historyDiff?.id == 'c:${commit.hash}:${change.path}') return;
    historyDiff = DiffTab(
      id: 'c:${commit.hash}:${change.path}',
      change: change,
      leftTitle: parent == null ? '(none)' : parent.substring(0, 8),
      rightTitle: commit.shortHash,
      loader: () async {
        final left = parent == null || change.kind == ChangeKind.added
            ? null
            : await repo.fileAt(parent, change.oldPath ?? change.path);
        final right =
            change.kind == ChangeKind.deleted ? null : await repo.fileAt(commit.hash, change.path);
        if (LfsPointer.parse(left) != null || LfsPointer.parse(right) != null) {
          final remote = primaryRemote ?? 'origin';
          return DiffContent(null, null,
              lfs: LfsDiff(
                _lfsSideFromPointer(left,
                    download: () =>
                        _lfsFetchVersion(remote, parent!, change.oldPath ?? change.path)),
                _lfsSideFromPointer(right,
                    download: () => _lfsFetchVersion(remote, commit.hash, change.path)),
              ));
        }
        return DiffContent(left, right);
      },
    );
    notifyListeners();
  }
}
