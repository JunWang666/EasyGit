import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';

/// Actions for a branch or tag, shared by the branch popup and the log's
/// branches tree. [context] must stay mounted after the menu closes.
List<IdeMenuItem> branchMenuItems(BuildContext context, RepoController ctrl, GitRef ref) {
  final c = IdeColors.of(context);
  final current = ctrl.currentBranchLabel;
  final isCurrent = ref.type == RefType.local && ref.isHead;
  final shortName = ref.name;

  Future<void> newBranchFrom() async {
    final result = await showNewBranchDialog(context, shortName);
    if (result != null) {
      await ctrl.createBranch(result.name, ref.name, checkout: result.checkout);
    }
  }

  Future<void> rename() async {
    final name = await showInputDialog(context,
        title: 'Rename Branch $shortName', label: 'New branch name:', initial: shortName,
        okLabel: 'Rename');
    if (name != null && name != shortName) await ctrl.renameBranch(ref, name);
  }

  Future<void> delete() async {
    final what = switch (ref.type) {
      RefType.local => 'branch',
      RefType.remote => 'remote branch',
      RefType.tag => 'tag',
    };
    final ok = await showConfirmDialog(context,
        title: 'Delete ${what[0].toUpperCase()}${what.substring(1)}',
        message: 'Delete $what "$shortName"?'
            '${ref.type == RefType.remote ? '\n\nThis deletes the branch on the remote.' : ''}',
        okLabel: 'Delete');
    if (!ok || !context.mounted) return;
    if (ref.type == RefType.local) {
      final merged = await _deleteLocal(context, ctrl, ref);
      if (!merged) return;
    } else {
      await ctrl.deleteRef(ref);
    }
  }

  Future<void> checkoutAndRebase() async {
    await ctrl.checkout(ref);
    await ctrl.rebase(current);
  }

  // Where this branch lives on a hosting service, if anywhere.
  final upstream = ref.type == RefType.remote ? ref.name : ref.upstream;
  final upstreamRemote =
      upstream != null && upstream.contains('/') ? upstream.substring(0, upstream.indexOf('/')) : null;
  final branchWeb = upstreamRemote == null ? null : ctrl.webFor(upstreamRemote);
  final branchOnRemote = upstreamRemote == null ? null : upstream!.substring(upstreamRemote.length + 1);
  final requestWeb = branchWeb ?? ctrl.webFor();

  return [
    if (!isCurrent)
      IdeMenuItem('Checkout', icon: Icons.login, onTap: () => ctrl.checkout(ref)),
    IdeMenuItem("New Branch from '$shortName'...", icon: Icons.add, onTap: newBranchFrom),
    if (!isCurrent && ref.type == RefType.local)
      IdeMenuItem("Checkout and Rebase onto '$current'", onTap: checkoutAndRebase),
    const IdeMenuItem.divider(),
    if (!isCurrent) ...[
      IdeMenuItem("Rebase '$current' onto '$shortName'",
          icon: Icons.low_priority, onTap: () => ctrl.rebase(ref.name)),
      IdeMenuItem("Merge '$shortName' into '$current'",
          icon: Icons.merge, onTap: () => ctrl.merge(ref.name)),
      const IdeMenuItem.divider(),
    ],
    if (ref.type == RefType.local) ...[
      IdeMenuItem('Push...',
          icon: Icons.north_east, iconColor: c.success, onTap: () => ctrl.pushBranch(ref)),
      if (requestWeb != null)
        IdeMenuItem('Create ${requestWeb.kind.requestName}...',
            icon: Icons.merge_type, onTap: () => ctrl.createRequest(ref)),
      IdeMenuItem('Rename...', icon: Icons.edit_outlined, onTap: rename),
    ],
    if (branchWeb != null && branchOnRemote != null)
      IdeMenuItem('Open on ${branchWeb.kind.shortLabel}',
          icon: hostingIcon(branchWeb.kind),
          onTap: () => ctrl.openUrl(branchWeb.branch(branchOnRemote))),
    if (!isCurrent) IdeMenuItem('Delete', icon: Icons.delete_outline, onTap: delete),
  ];
}

/// Deletes a local branch, offering a force delete if it is not merged.
Future<bool> _deleteLocal(BuildContext context, RepoController ctrl, GitRef ref) async {
  try {
    await ctrl.repo.deleteBranch(ref);
    await ctrl.refreshAll();
    return true;
  } on GitException catch (e) {
    if (!context.mounted) return false;
    if (!e.message.contains('not fully merged')) {
      await showConfirmDialog(context, title: 'Delete failed', message: e.message);
      return false;
    }
    final force = await showConfirmDialog(context,
        title: 'Branch Is Not Fully Merged',
        message: 'Branch "${ref.name}" is not fully merged. Delete it anyway?',
        okLabel: 'Delete');
    if (force) await ctrl.deleteRef(ref, force: true);
    return force;
  }
}
