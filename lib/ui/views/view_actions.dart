import 'dart:io';

import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../shell/repo_flows.dart';
import '../shell/worktree_dialog.dart';
import '../widgets/dialogs.dart';

Future<void> newBranchFlow(BuildContext context, RepoController ctrl) async {
  final result = await showNewBranchDialog(context, ctrl.currentBranchLabel);
  if (result != null) await ctrl.createBranch(result.name, 'HEAD', checkout: result.checkout);
}

Future<void> stashFlow(BuildContext context, RepoController ctrl) async {
  final message = await showInputDialog(context,
      title: 'Stash Changes', label: 'Message (optional):', initial: 'WIP', okLabel: 'Stash');
  if (message != null) await ctrl.stash(message);
}

Future<void> addWorktreeFlow(BuildContext context, RepoController ctrl, ReposState repos,
    {String? branch}) async {
  final request = await showAddWorktreeDialog(context, ctrl, initialBranch: branch);
  if (request == null) return;
  final ok = await ctrl.addWorktree(request.path, request.commitish, newBranch: request.newBranch);
  if (ok && request.open && context.mounted) await openRepositoryAt(context, repos, request.path);
}

Future<void> removeWorktreeFlow(
    BuildContext context, RepoController ctrl, ReposState repos, WorktreeInfo w) async {
  final ok = await showConfirmDialog(context,
      title: 'Remove Worktree',
      message: 'Remove the worktree at\n${w.path}?\n\n'
          'The folder is deleted. The branch${w.branch == null ? '' : ' "${w.branch}"'} is kept.',
      okLabel: 'Remove');
  if (!ok) return;
  // Close it in the sidebar first so no git process holds the folder.
  final open = repos.repos.where((r) => ReposState.samePath(r.repo.root, w.path)).firstOrNull;
  if (open != null) await repos.remove(open);
  try {
    await ctrl.repo.removeWorktree(w.path);
    await ctrl.refreshAll();
  } on GitException catch (e) {
    if (!context.mounted) return;
    final force = await showConfirmDialog(context,
        title: 'Worktree Has Changes',
        message: '${e.message}\n\nRemove it anyway? Uncommitted changes in it will be lost.',
        okLabel: 'Force Remove');
    if (force) await ctrl.removeWorktree(w, force: true);
  }
}

void revealPath(RepoController ctrl, String path) =>
    ctrl.openUrl(Uri.directory(path, windows: Platform.isWindows).toString());
