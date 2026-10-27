import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../diff/diff_view.dart';
import '../format.dart';
import '../log/commit_details_panel.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';
import 'view_actions.dart';

/// Stashes tab: the stash list, and the selected stash's files and diff.
class StashesView extends StatelessWidget {
  const StashesView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return SplitPane(
      axis: Axis.horizontal,
      initialSize: 340,
      minSize: 240,
      minOther: 300,
      first: Container(
        color: c.panelBg,
        child: ListenableBuilder(listenable: ctrl, builder: (context, _) => _list(context)),
      ),
      second: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final selected = ctrl.stashes.where((s) => s.hash == ctrl.selectedHash).firstOrNull;
          if (selected == null) {
            return Container(
              color: c.editorBg,
              child: EmptyHint(ctrl.stashes.isEmpty
                  ? 'No stashes. Stash saves your local changes so you can switch tasks.'
                  : 'Select a stash to see its changes'),
            );
          }
          final diff = ctrl.historyDiff;
          return SplitPane(
            axis: Axis.horizontal,
            initialSize: 300,
            minSize: 220,
            minOther: 260,
            first: Container(color: c.panelBg, child: CommitDetailsPanel(ctrl: ctrl)),
            second: diff == null
                ? Container(color: c.editorBg, child: const EmptyHint('Select a file'))
                : DiffView(key: ValueKey(diff.id), tab: diff),
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context) {
    final c = IdeColors.of(context);
    final hasChanges = ctrl.status?.changes.isNotEmpty ?? false;
    return Column(children: [
      PanelHeader(
        title: 'Stashes',
        trailing: IdeButton(
          label: 'Stash Changes...',
          onPressed: hasChanges && ctrl.busy == null ? () => stashFlow(context, ctrl) : null,
        ),
      ),
      Container(height: 1, color: c.splitter),
      Expanded(
        child: ctrl.stashes.isEmpty
            ? const EmptyHint('No stashes')
            : ListView(children: [for (final s in ctrl.stashes) _row(context, s)]),
      ),
    ]);
  }

  Widget _row(BuildContext context, StashEntry s) {
    final c = IdeColors.of(context);
    final selected = ctrl.selectedHash == s.hash;
    return HoverBuilder(
      builder: (context, hovered) => ListRow(
        height: 48,
        selected: selected,
        onTap: () => ctrl.showStash(s),
        onContextMenu: (pos) => showIdeMenu(context, pos, [
          IdeMenuItem('Apply', icon: Icons.unarchive_outlined, onTap: () => ctrl.applyStash(s)),
          IdeMenuItem('Pop (apply and drop)', onTap: () => ctrl.applyStash(s, pop: true)),
          const IdeMenuItem.divider(),
          IdeMenuItem('Drop...', icon: Icons.delete_outline, onTap: () => _drop(context, s)),
        ]),
        child: Row(children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: c.icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${s.ref} · ${formatLogDate(s.date)}',
                    style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
              ],
            ),
          ),
          if (hovered || selected) ...[
            IdeIconButton(
                icon: Icons.unarchive_outlined,
                tooltip: 'Apply',
                size: 26,
                onPressed: () => ctrl.applyStash(s)),
            IdeIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Drop',
                size: 26,
                onPressed: () => _drop(context, s)),
          ],
        ]),
      ),
    );
  }

  Future<void> _drop(BuildContext context, StashEntry s) async {
    final ok = await showConfirmDialog(context,
        title: 'Drop Stash',
        message: 'Drop ${s.ref} "${s.message}"? This cannot be undone.',
        okLabel: 'Drop');
    if (ok) await ctrl.dropStash(s);
  }
}
