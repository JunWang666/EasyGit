import 'package:flutter/material.dart';

import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../commit/commit_panel.dart';
import '../diff/diff_view.dart';
import '../format.dart';
import '../lfs/lfs_dialog.dart';
import 'branches_view.dart';
import 'stashes_view.dart';
import 'worktrees_view.dart';
import '../log/commit_details_panel.dart';
import '../log/commit_log_view.dart';
import '../widgets/common.dart';

/// The main area for a repository: a tab bar and the selected view.
class RepoMain extends StatelessWidget {
  const RepoMain({super.key, required this.ctrl, required this.repos});

  final RepoController ctrl;
  final ReposState repos;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final counts = {
          RepoView.changes: ctrl.status?.changes.length ?? 0,
          RepoView.branches: ctrl.localBranches.length,
          RepoView.stashes: ctrl.stashes.length,
          RepoView.worktrees: ctrl.worktrees.length,
        };
        return Column(children: [
          Container(
            height: 38,
            color: c.panelBg,
            padding: const EdgeInsets.only(left: 6),
            child: Row(children: [
              for (final v in RepoView.values)
                _Tab(
                  label: v.label,
                  count: counts[v],
                  highlight: v == RepoView.changes && (counts[v] ?? 0) > 0,
                  active: ctrl.view == v,
                  shortcut: shortcutLabel('${v.index + 1}'),
                  onTap: () => ctrl.setView(v),
                ),
              const Spacer(),
              if (ctrl.lfs.usesLfs) _LfsPill(ctrl: ctrl),
              const SizedBox(width: 8),
            ]),
          ),
          Container(height: 1, color: c.splitter),
          if (ctrl.lfs.needsSetup) _LfsSetupStrip(ctrl: ctrl),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey((ctrl, ctrl.view)),
              child: switch (ctrl.view) {
                RepoView.changes => ChangesView(ctrl: ctrl),
                RepoView.history => HistoryView(ctrl: ctrl),
                RepoView.branches => BranchesView(ctrl: ctrl, repos: repos),
                RepoView.stashes => StashesView(ctrl: ctrl),
                RepoView.worktrees => WorktreesView(ctrl: ctrl, repos: repos),
              },
            ),
          ),
        ]);
      },
    );
  }
}

/// Compact LFS status in the tab bar; opens the LFS dialog.
class _LfsPill extends StatelessWidget {
  const _LfsPill({required this.ctrl});

  final RepoController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final lfs = ctrl.lfs;
    final missing = lfs.missing.length;
    final warn = lfs.needsSetup;
    final label = warn
        ? 'LFS · setup needed'
        : (missing > 0 ? 'LFS · $missing not downloaded' : 'LFS · ${lfs.files.length} files');
    final color = warn ? c.warning : (missing > 0 ? c.accent : c.textSecondary);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: () => showLfsDialog(context, ctrl),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: hovered ? c.hover : null,
            border: Border.all(color: color.withAlpha(140)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(warn ? Icons.warning_amber : (missing > 0 ? Icons.cloud_download_outlined : Icons.cloud_done_outlined),
                size: 13, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ]),
        ),
      ),
    );
  }
}

/// Shown when the repository uses LFS but this machine is not ready for it.
class _LfsSetupStrip extends StatelessWidget {
  const _LfsSetupStrip({required this.ctrl});

  final RepoController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final installed = ctrl.lfs.installed;
    return Container(
      color: c.warning.withAlpha(30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Icon(Icons.warning_amber, size: 16, color: c.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(installed
              ? 'This repository uses Git LFS, but LFS is not set up here. Pushes would not upload large files.'
              : 'This repository uses Git LFS, but git-lfs is not installed. Large files show as small pointer files.'),
        ),
        if (installed)
          IdeButton(label: 'Set Up LFS', primary: true, onPressed: ctrl.lfsInstallHooks)
        else
          IdeButton(label: 'Details...', onPressed: () => showLfsDialog(context, ctrl)),
      ]),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.highlight,
    required this.active,
    required this.shortcut,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool highlight;
  final bool active;
  final String shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return Tooltip(
      message: shortcut,
      waitDuration: const Duration(milliseconds: 800),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: hovered && !active ? c.hover.withAlpha(120) : null,
              border: Border(
                bottom: BorderSide(color: active ? c.accent : Colors.transparent, width: 2),
              ),
            ),
            child: Row(children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                      color: active ? c.text : c.textSecondary)),
              if (count != null && count! > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: highlight ? c.accent.withAlpha(60) : c.hover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$count', style: TextStyle(fontSize: 11, color: c.text)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Working tree: changed files and commit box on the left, the selected
/// file's diff on the right.
class ChangesView extends StatelessWidget {
  const ChangesView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return SplitPane(
      axis: Axis.horizontal,
      initialSize: 380,
      minSize: 260,
      minOther: 300,
      first: Container(color: c.panelBg, child: CommitPanel(ctrl: ctrl)),
      second: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          final diff = ctrl.changesDiff;
          if (diff == null) {
            return Container(
              color: c.editorBg,
              child: EmptyHint(ctrl.status?.changes.isEmpty ?? false
                  ? 'Working tree clean. Nothing to commit.'
                  : 'Select a file to see its changes'),
            );
          }
          return DiffView(key: ValueKey(diff.id), tab: diff);
        },
      ),
    );
  }
}

/// History: the commit graph on top; the selected commit's message and files
/// with the selected file's diff below.
class HistoryView extends StatelessWidget {
  const HistoryView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return SplitPane(
      axis: Axis.vertical,
      sizeOfSecond: true,
      initialSize: 360,
      minSize: 160,
      minOther: 160,
      first: Container(color: c.panelBg, child: CommitLogView(ctrl: ctrl)),
      second: SplitPane(
        axis: Axis.horizontal,
        initialSize: 360,
        minSize: 240,
        minOther: 300,
        first: Container(color: c.panelBg, child: CommitDetailsPanel(ctrl: ctrl)),
        second: ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            final diff = ctrl.historyDiff;
            if (diff == null) {
              return Container(
                color: c.editorBg,
                child: EmptyHint(ctrl.selectedHash == null
                    ? 'Select a commit in the graph'
                    : 'Select a file to see its changes'),
              );
            }
            return DiffView(key: ValueKey(diff.id), tab: diff);
          },
        ),
      ),
    );
  }
}
