import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../shell/repo_flows.dart';
import '../shell/worktree_dialog.dart';
import '../widgets/common.dart';
import '../widgets/menus.dart';
import 'view_actions.dart';

/// Worktrees tab: every checkout of this repository, with open/remove actions.
class WorktreesView extends StatelessWidget {
  const WorktreesView({super.key, required this.ctrl, required this.repos});

  final RepoController ctrl;
  final ReposState repos;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) => Container(
        color: c.editorBg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: c.panelBg,
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(children: [
              Expanded(
                child: Text(
                  'Worktrees are extra checkouts of this repository in other folders, so you can '
                  'work on several branches at the same time without stashing.',
                  style: TextStyle(color: c.textSecondary),
                ),
              ),
              const SizedBox(width: 12),
              if (ctrl.worktrees.any((w) => w.prunable)) ...[
                IdeButton(label: 'Prune Missing', onPressed: ctrl.pruneWorktrees),
                const SizedBox(width: 6),
              ],
              IdeButton(
                label: 'Add Worktree...',
                primary: true,
                onPressed: () => addWorktreeFlow(context, ctrl, repos),
              ),
            ]),
          ),
          Container(height: 1, color: c.splitter),
          Expanded(
            child: ListView(children: [for (final w in ctrl.worktrees) _row(context, w)]),
          ),
        ]),
      ),
    );
  }

  Widget _row(BuildContext context, WorktreeInfo w) {
    final c = IdeColors.of(context);
    final isCurrent = isCurrentWorktree(ctrl, w);
    final inSidebar = repos.repos.any((r) => ReposState.samePath(r.repo.root, w.path));
    final canOpen = !isCurrent && !w.isBare && !w.prunable;

    Widget chip(String text, Color color) => Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(color: color.withAlpha(140)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
        );

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Icon(w.isMain ? Icons.home_outlined : Icons.account_tree_outlined,
            size: 20, color: isCurrent ? c.accent : c.icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(w.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: w.prunable ? c.textDisabled : c.text)),
                ),
                const SizedBox(width: 8),
                Icon(Icons.call_split, size: 13, color: c.textSecondary),
                const SizedBox(width: 3),
                Text(
                  w.branch ??
                      'detached at ${w.head.length > 8 ? w.head.substring(0, 8) : w.head}',
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary),
                ),
                if (isCurrent) chip('this window', c.accent),
                if (w.isMain) chip('main', c.textSecondary),
                if (w.locked) chip('locked', c.warning),
                if (w.prunable) chip('missing', c.error),
              ]),
              const SizedBox(height: 2),
              Text(w.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 11.5, color: c.textSecondary)),
            ],
          ),
        ),
        if (canOpen)
          IdeButton(
            label: inSidebar ? 'Switch to' : 'Open',
            onPressed: () => openRepositoryAt(context, repos, w.path),
          ),
        const SizedBox(width: 4),
        Builder(
          builder: (context) => IdeIconButton(
            icon: Icons.more_horiz,
            tooltip: 'More',
            onPressed: () {
              final box = context.findRenderObject()! as RenderBox;
              showIdeMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
                IdeMenuItem('Show in File Manager',
                    icon: Icons.folder_outlined, onTap: () => revealPath(ctrl, w.path)),
                IdeMenuItem('Copy Path',
                    icon: Icons.copy,
                    onTap: () => Clipboard.setData(ClipboardData(text: w.path))),
                if (!w.isMain && !isCurrent) ...[
                  const IdeMenuItem.divider(),
                  IdeMenuItem('Remove Worktree...',
                      icon: Icons.delete_outline,
                      onTap: () => removeWorktreeFlow(context, ctrl, repos, w)),
                ],
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
