/// Data types shared by the git layer and the UI.
library;

enum ChangeKind {
  modified,
  added,
  deleted,
  renamed,
  copied,
  typeChanged,
  untracked,
  conflicted,
}

ChangeKind changeKindFromLetter(String letter) => switch (letter) {
      'A' => ChangeKind.added,
      'D' => ChangeKind.deleted,
      'R' => ChangeKind.renamed,
      'C' => ChangeKind.copied,
      'T' => ChangeKind.typeChanged,
      'U' => ChangeKind.conflicted,
      _ => ChangeKind.modified,
    };

/// A changed file, either in the working tree or inside a commit.
class FileChange {
  const FileChange({
    required this.path,
    required this.kind,
    this.oldPath,
    this.staged = false,
    this.unstaged = false,
  });

  /// Path relative to the repository root, always with `/` separators.
  final String path;
  final String? oldPath;
  final ChangeKind kind;
  final bool staged;
  final bool unstaged;

  String get name {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  String get directory {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  bool get isUntracked => kind == ChangeKind.untracked;
}

enum RefLabelType { head, local, remote, tag }

/// A decoration shown next to a commit in the log.
class RefLabel {
  const RefLabel(this.name, this.type, {this.isCurrent = false});

  final String name;
  final RefLabelType type;
  final bool isCurrent;
}

class CommitInfo {
  const CommitInfo({
    required this.hash,
    required this.parents,
    required this.author,
    required this.email,
    required this.date,
    required this.subject,
    this.refs = const [],
  });

  final String hash;
  final List<String> parents;
  final String author;
  final String email;
  final DateTime date;
  final String subject;
  final List<RefLabel> refs;

  String get shortHash => hash.length > 8 ? hash.substring(0, 8) : hash;
  bool get isMerge => parents.length > 1;
}

class CommitDetails {
  const CommitDetails({
    required this.info,
    required this.body,
    required this.committer,
    required this.commitDate,
    required this.files,
  });

  final CommitInfo info;
  final String body;
  final String committer;
  final DateTime commitDate;
  final List<FileChange> files;
}

enum RefType { local, remote, tag }

/// A branch or tag from `git for-each-ref`.
class GitRef {
  const GitRef({
    required this.fullName,
    required this.name,
    required this.hash,
    required this.type,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.upstreamGone = false,
    this.isHead = false,
    this.subject = '',
    this.date,
  });

  /// Subject of the commit (or annotated tag) the ref points to.
  final String subject;
  final DateTime? date;

  final String fullName;

  /// Short name: `main`, `origin/main` or `v1.0`.
  final String name;
  final String hash;
  final RefType type;
  final String? upstream;
  final int ahead;
  final int behind;
  final bool upstreamGone;
  final bool isHead;

  /// For remote branches, the remote part of [name] (`origin`).
  String get remote {
    final i = name.indexOf('/');
    return i < 0 ? name : name.substring(0, i);
  }

  /// For remote branches, [name] without the remote prefix.
  String get branchName {
    if (type != RefType.remote) return name;
    final i = name.indexOf('/');
    return i < 0 ? name : name.substring(i + 1);
  }
}

/// An entry of `git stash list`.
class StashEntry {
  const StashEntry({required this.ref, required this.hash, required this.date, required this.message});

  /// `stash@{0}`.
  final String ref;
  final String hash;
  final DateTime date;
  final String message;
}

/// An entry of `git worktree list`.
class WorktreeInfo {
  const WorktreeInfo({
    required this.path,
    required this.head,
    this.branch,
    this.isMain = false,
    this.isBare = false,
    this.locked = false,
    this.prunable = false,
  });

  /// Absolute path, with `/` separators as git prints them.
  final String path;
  final String head;

  /// Short branch name, or null when HEAD is detached.
  final String? branch;
  final bool isMain;
  final bool isBare;
  final bool locked;
  final bool prunable;

  String get name => path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path;
}

enum RepoState { normal, merging, rebasing, cherryPicking, reverting }

class RepoStatus {
  const RepoStatus({
    required this.branch,
    required this.headHash,
    required this.upstream,
    required this.ahead,
    required this.behind,
    required this.changes,
    required this.state,
  });

  /// Current branch, or null when HEAD is detached.
  final String? branch;
  final String? headHash;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<FileChange> changes;
  final RepoState state;

  bool get detached => branch == null;
  bool get hasCommits => headHash != null;

  String get headLabel {
    if (branch != null) return branch!;
    if (headHash != null) {
      return headHash!.length > 8 ? headHash!.substring(0, 8) : headHash!;
    }
    return 'HEAD';
  }
}

class GitException implements Exception {
  const GitException(this.command, this.message, [this.exitCode = 1]);

  final String command;
  final String message;
  final int exitCode;

  @override
  String toString() => message;
}

/// One entry of the Git console (commands the user triggered).
class GitCommandLog {
  const GitCommandLog({
    required this.time,
    required this.command,
    required this.exitCode,
    required this.output,
  });

  final DateTime time;
  final String command;
  final int exitCode;
  final String output;

  bool get failed => exitCode != 0;
}
