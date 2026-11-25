import 'git_runner.dart';
import 'lfs.dart';
import 'models.dart';

enum ResetMode { soft, mixed, hard, keep }

/// Commit author settings of a repository.
class RepoIdentity {
  const RepoIdentity(
      {this.localName, this.localEmail, this.globalName, this.globalEmail});

  /// Set in the repository's own config; null when it uses the global one.
  final String? localName;
  final String? localEmail;
  final String? globalName;
  final String? globalEmail;

  bool get hasLocal => localName != null || localEmail != null;
  String? get name => localName ?? globalName;
  String? get email => localEmail ?? globalEmail;
}

/// The git operations EasyGit needs, independent of how they are implemented.
///
/// [GitRepository] implements this with the git command line. A libgit2
/// implementation over `dart:ffi` can provide the same API where spawning
/// processes is impossible, such as iOS, and in sandboxed or otherwise
/// shell-less environments.
abstract interface class GitBackend {
  /// Absolute path of the working tree root.
  String get root;

  /// Absolute path of the `.git` directory.
  String get gitDir;

  String get name;

  /// Commands run by this backend, shown in the Git console.
  set onLog(void Function(GitCommandLog log)? callback);

  /// HTTPS credentials for this repository only (null: all signed-in accounts).
  set credentialOverride(List<GitCredential>? value);

  /// Credentials used by git-lfs for this repository's LFS server only.
  set lfsCredentials(List<GitCredential> value);

  /// Interrupts the operations currently running on this backend.
  void cancel();

  Future<RepoStatus> status();
  Future<List<GitRef>> refs();
  Future<List<String>> remotes();
  Future<Map<String, String>> remoteUrls();
  Future<void> addRemote(String name, String url);
  Future<void> setRemoteUrl(String name, String url);
  Future<void> renameRemote(String from, String to);
  Future<void> removeRemote(String name);
  Future<String?> remoteDefaultBranch(String remote);

  Future<List<CommitInfo>> log({String? branch, int limit = 5000});
  Future<CommitDetails> commitDetails(String hash);
  Future<String> lastCommitMessage();
  Future<String?> fileAt(String rev, String path);

  Future<String?> readWorkingFile(String path);
  Future<int?> workingFileSize(String path);
  Future<void> writeWorkingFile(String path, String content);
  Future<void> deleteWorkingFile(String path);

  Future<void> commit(String message, List<FileChange> files,
      {bool amend = false, String? authorName, String? authorEmail});
  Future<void> rollback(List<FileChange> files);
  Future<void> addToVcs(List<String> paths);

  Future<void> stash(String message);
  Future<void> stashPop([String? ref]);
  Future<void> stashApply(String ref);
  Future<void> stashDrop(String ref);
  Future<List<StashEntry>> stashes();

  Future<List<WorktreeInfo>> worktrees();
  Future<void> addWorktree(String path, String commitish, {String? newBranch});
  Future<void> removeWorktree(String path, {bool force = false});
  Future<void> pruneWorktrees();

  Future<void> fetch({void Function(String)? onProgress});
  Future<void> pull({bool rebase = false, void Function(String)? onProgress});
  Future<void> push({bool force = false, void Function(String)? onProgress});
  Future<void> pushBranch(GitRef ref, {void Function(String)? onProgress});

  Future<RepoIdentity> identity();
  Future<void> setLocalIdentity(String? name, String? email);
  Future<String?> accountId();
  Future<void> setAccountId(String? id);

  Future<void> checkout(String ref);
  Future<void> checkoutRevision(String rev);
  Future<void> checkoutRemote(GitRef remote, List<GitRef> all);
  Future<void> createBranch(String name, String startPoint,
      {required bool checkout});
  Future<void> renameBranch(String from, String to);
  Future<void> deleteBranch(GitRef ref, {bool force = false});
  Future<void> merge(String ref);
  Future<void> rebase(String onto);
  Future<void> abortOperation(RepoState state);
  Future<void> continueOperation(RepoState state);
  Future<void> cherryPick(String hash);
  Future<void> revert(String hash);
  Future<void> reset(String hash, ResetMode mode);
  Future<void> createTag(String name, String hash);

  Future<bool> usesLfs();
  Future<List<String>> lfsPatterns();
  Future<bool> lfsHooksInstalled();
  Future<void> lfsInstallHooks();
  Future<List<LfsFile>> lfsFiles();
  Future<LfsEnv> lfsEnv();
  Future<Set<String>> lfsTrackedPaths(Iterable<String> paths);
  Future<void> lfsTrack(List<String> patterns);
  Future<void> lfsPull([List<String>? paths, void Function(String)? onProgress]);
  Future<void> lfsPush(String remote, List<String> oids,
      {void Function(String)? onProgress});
  Future<LfsCleanResult> lfsClean(List<LfsFile> files,
      {Set<String> changedPaths = const {}});
  Future<void> lfsFetch(String remote, String rev, String path,
      {void Function(String)? onProgress});
  Future<LfsServerConfig> lfsServerConfig();
  Future<void> setLfsServer(LfsUrlSource source, String url);
}
