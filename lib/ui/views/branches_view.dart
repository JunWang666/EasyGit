import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../branches/branch_actions.dart';
import '../format.dart';
import '../remotes/manage_remotes_dialog.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';
import 'view_actions.dart';

enum _RefTab { local, remote, tags }

/// Branches tab: local branches, remote branches (by remote) and tags in a table.
class BranchesView extends StatefulWidget {
  const BranchesView({super.key, required this.ctrl, required this.repos});

  final RepoController ctrl;
  final ReposState repos;

  @override
  State<BranchesView> createState() => _BranchesViewState();
}

class _BranchesViewState extends State<BranchesView> {
  var _tab = _RefTab.local;
  var _query = '';
  String? _selected;

  RepoController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final q = _query.toLowerCase();
        bool match(GitRef r) => q.isEmpty || r.name.toLowerCase().contains(q);
        final local = ctrl.localBranches.where(match).toList()
          ..sort((a, b) => a.isHead ? -1 : (b.isHead ? 1 : _byDate(a, b)));
        final remote = ctrl.remoteBranches.where(match).toList();
        final tags = ctrl.tags.where(match).toList()..sort(_byDate);

        final rows = <Widget>[];
        switch (_tab) {
          case _RefTab.local:
            rows.addAll(local.map(_row));
          case _RefTab.remote:
            final byRemote = <String, List<GitRef>>{};
            for (final r in remote) {
              byRemote.putIfAbsent(r.remote, () => []).add(r);
            }
            for (final name in ctrl.remoteUrls.keys) {
              final list = (byRemote[name] ?? [])..sort(_byDate);
              rows.add(_remoteHeader(name, ctrl.remoteUrls[name]!, list.length));
              rows.addAll(list.map(_row));
            }
          case _RefTab.tags:
            rows.addAll(tags.map(_row));
        }

        return Container(
          color: c.editorBg,
          child: Column(children: [
            Container(
              height: 44,
              color: c.panelBg,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(children: [
                _segment('Local', ctrl.localBranches.length, _RefTab.local),
                _segment('Remote', ctrl.remoteBranches.length, _RefTab.remote),
                _segment('Tags', ctrl.tags.length, _RefTab.tags),
                const SizedBox(width: 12),
                IdeTextField(
                  width: 240,
                  hint: 'Filter',
                  prefixIcon: Icons.search,
                  onChanged: (v) => setState(() => _query = v),
                ),
                const Spacer(),
                IdeButton(label: 'New Branch...', onPressed: () => newBranchFlow(context, ctrl)),
                const SizedBox(width: 6),
                IdeButton(label: 'Fetch', onPressed: ctrl.busy == null ? ctrl.fetch : null),
                const SizedBox(width: 6),
                IdeButton(
                    label: 'Remotes...', onPressed: () => showManageRemotesDialog(context, ctrl)),
              ]),
            ),
            Container(height: 1, color: c.splitter),
            _columnHeader(),
            Container(height: 1, color: c.border),
            Expanded(
              child: rows.isEmpty
                  ? EmptyHint(switch (_tab) {
                      _RefTab.local => 'No branches yet. Make a first commit.',
                      _RefTab.remote => ctrl.remoteUrls.isEmpty
                          ? 'No remotes. Use "Remotes..." to add one.'
                          : 'No remote branches. Try Fetch.',
                      _RefTab.tags => 'No tags',
                    })
                  : ListView(children: rows),
            ),
          ]),
        );
      },
    );
  }

  static int _byDate(GitRef a, GitRef b) =>
      (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970));

  Widget _segment(String label, int count, _RefTab tab) {
    final c = IdeColors.of(context);
    final active = _tab == tab;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: () => setState(() => _tab = tab),
        child: Container(
          height: 28,
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? c.selection : (hovered ? c.hover : null),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Text(label, style: TextStyle(fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ]),
        ),
      ),
    );
  }

  Widget _columnHeader() {
    final c = IdeColors.of(context);
    final style = TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600);
    return Container(
      height: 28,
      color: c.panelBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(flex: 3, child: Text('Name', style: style)),
        Expanded(flex: 2, child: Text(_tab == _RefTab.local ? 'Tracking' : '', style: style)),
        Expanded(flex: 4, child: Text('Last commit', style: style)),
        SizedBox(width: 150, child: Text('Date', style: style)),
        const SizedBox(width: 96),
      ]),
    );
  }

  Widget _remoteHeader(String name, String url, int count) {
    final c = IdeColors.of(context);
    final web = ctrl.webFor(name);
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 16, right: 8),
      color: c.panelBg.withAlpha(140),
      child: Row(children: [
        Icon(Icons.cloud_outlined, size: 15, color: c.icon),
        const SizedBox(width: 8),
        Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12, color: c.textSecondary)),
        ),
        Text('$count', style: TextStyle(fontSize: 12, color: c.textSecondary)),
        if (web != null)
          IdeIconButton(
            icon: Icons.open_in_new,
            tooltip: 'Open on ${web.kind.shortLabel}',
            size: 24,
            iconSize: 14,
            onPressed: () => ctrl.openUrl(web.home),
          ),
      ]),
    );
  }

  Widget _row(GitRef ref) {
    final c = IdeColors.of(context);
    final key = ref.fullName;
    final icon = switch (ref.type) {
      RefType.tag => Icon(Icons.sell_outlined, size: 15, color: c.refTag),
      RefType.remote => Icon(Icons.call_split, size: 15, color: c.refRemote),
      RefType.local => ref.isHead
          ? Icon(Icons.local_offer, size: 15, color: c.refHead)
          : Icon(Icons.call_split, size: 15, color: c.refLocal),
    };
    final worktree = ref.type == RefType.local && !ref.isHead
        ? ctrl.worktrees.where((w) => w.branch == ref.name).firstOrNull
        : null;
    final secondary = TextStyle(fontSize: 12.5, color: c.textSecondary);

    return HoverBuilder(
      builder: (context, hovered) => ListRow(
        height: 34,
        indent: 8,
        selected: _selected == key,
        onTap: () => setState(() => _selected = key),
        onDoubleTap: ref.isHead || worktree != null ? null : () => ctrl.checkout(ref),
        onContextMenu: (pos) {
          setState(() => _selected = key);
          showIdeMenu(context, pos, [
            ...branchMenuItems(context, ctrl, ref),
            const IdeMenuItem.divider(),
            IdeMenuItem('Show in History',
                icon: Icons.timeline, onTap: () => _showInHistory(ref)),
            IdeMenuItem('Show Only This Branch in History',
                icon: Icons.filter_alt_outlined,
                onTap: () {
                  ctrl.setView(RepoView.history);
                  ctrl.setBranchFilter(ref.name);
                }),
            if (ref.type == RefType.local && !ref.isHead && worktree == null)
              IdeMenuItem('New Worktree for This Branch...',
                  icon: Icons.account_tree_outlined,
                  onTap: () => addWorktreeFlow(context, ctrl, widget.repos, branch: ref.name)),
          ]);
        },
        child: Row(children: [
          Expanded(
            flex: 3,
            child: Row(children: [
              icon,
              const SizedBox(width: 8),
              Flexible(
                child: Text(ref.type == RefType.remote ? ref.branchName : ref.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: ref.isHead ? FontWeight.w600 : FontWeight.normal)),
              ),
              if (ref.isHead) _pill('current', c.accent),
              if (worktree != null)
                Tooltip(message: 'Checked out in ${worktree.path}', child: _pill('worktree', c.textSecondary)),
            ]),
          ),
          Expanded(
            flex: 2,
            child: ref.type != RefType.local
                ? const SizedBox()
                : Row(children: [
                    Flexible(
                      child: Text(ref.upstream ?? '—',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                    ),
                    if (ref.behind > 0)
                      Text('  ↓${ref.behind}', style: TextStyle(fontSize: 12, color: c.accent)),
                    if (ref.ahead > 0)
                      Text('  ↑${ref.ahead}', style: TextStyle(fontSize: 12, color: c.success)),
                    if (ref.upstreamGone) Text('  gone', style: secondary),
                  ]),
          ),
          Expanded(
            flex: 4,
            child: Text(ref.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
          ),
          SizedBox(
            width: 150,
            child: Text(ref.date == null ? '' : formatLogDate(ref.date!), style: secondary),
          ),
          SizedBox(
            width: 96,
            child: Opacity(
              opacity: hovered || _selected == key ? 1 : 0,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (!ref.isHead && worktree == null)
                  IdeIconButton(
                    icon: Icons.login,
                    tooltip: ref.type == RefType.remote
                        ? 'Check out as local branch'
                        : 'Check out',
                    size: 26,
                    onPressed: () => ctrl.checkout(ref),
                  ),
                IdeIconButton(
                  icon: Icons.timeline,
                  tooltip: 'Show in History',
                  size: 26,
                  onPressed: () => _showInHistory(ref),
                ),
                if (!ref.isHead && ref.type != RefType.remote)
                  IdeIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Delete',
                    size: 26,
                    onPressed: () => _delete(ref),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: color.withAlpha(140)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
      );

  void _showInHistory(GitRef ref) {
    ctrl.setView(RepoView.history);
    ctrl.reveal(ref.hash);
  }

  Future<void> _delete(GitRef ref) async {
    // Reuse the branch menu's delete flow, which handles unmerged branches.
    final delete = branchMenuItems(context, ctrl, ref).where((i) => i.label == 'Delete').firstOrNull;
    if (delete?.onTap != null) {
      delete!.onTap!();
    } else {
      await showConfirmDialog(context, title: 'Delete', message: 'This ref cannot be deleted here.');
    }
  }
}
