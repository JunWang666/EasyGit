import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/menus.dart';
import 'commit_log_view.dart';

/// Right side of the Git Log: changed files of the selected commit and its
/// full message and metadata.
class CommitDetailsPanel extends StatefulWidget {
  const CommitDetailsPanel({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  State<CommitDetailsPanel> createState() => _CommitDetailsPanelState();
}

class _CommitDetailsPanelState extends State<CommitDetailsPanel> {
  RepoController get ctrl => widget.ctrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        if (ctrl.selectedHash == null) {
          return const EmptyHint('Select a commit to view changes');
        }
        final details = ctrl.details;
        if (details == null) {
          return const Center(
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
        }
        return SplitPane(
          axis: Axis.vertical,
          initialSize: 150,
          minSize: 70,
          minOther: 80,
          first: _message(details),
          second: _files(details),
        );
      },
    );
  }

  Widget _files(CommitDetails details) {
    final c = IdeColors.of(context);
    final files = details.files;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Text('${files.length} file${files.length == 1 ? '' : 's'} changed',
                style: TextStyle(color: c.textSecondary)),
            if (details.info.isMerge)
              Text('  (vs first parent)', style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ]),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: files.length,
          itemExtent: 24,
          itemBuilder: (context, i) {
            final f = files[i];
            return ListRow(
              selected: ctrl.historyDiff?.change.path == f.path,
              onTap: () => ctrl.openCommitDiff(details.info, f),
              onContextMenu: (pos) {
                ctrl.openCommitDiff(details.info, f);
                final web = ctrl.webFor();
                showIdeMenu(context, pos, [
                  IdeMenuItem('Show Diff',
                      icon: Icons.compare_arrows,
                      onTap: () => ctrl.openCommitDiff(details.info, f)),
                  IdeMenuItem('Copy Path',
                      icon: Icons.copy,
                      onTap: () => Clipboard.setData(ClipboardData(text: f.path))),
                  if (web != null && f.kind != ChangeKind.deleted)
                    IdeMenuItem('Open on ${web.kind.shortLabel}',
                        icon: hostingIcon(web.kind),
                        onTap: () => ctrl.openUrl(web.file(details.info.hash, f.path))),
                ]);
              },
              child: FileChangeLabel(change: f, lfs: ctrl.lfs.isTracked(f.path)),
            );
          },
        ),
      ),
    ]);
  }

  Widget _message(CommitDetails d) {
    final c = IdeColors.of(context);
    final info = d.info;
    final secondary = TextStyle(color: c.textSecondary);
    return Container(
      color: c.panelBg,
      child: SelectionArea(
        child: ListView(padding: const EdgeInsets.all(12), children: [
          Text(info.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (d.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(d.body, style: monoStyle(context, size: 12.5)),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Text(info.shortHash, style: monoStyle(context, size: 12, color: c.accent)),
            const SizedBox(width: 6),
            IdeIconButton(
              icon: Icons.copy,
              tooltip: 'Copy full hash',
              size: 22,
              iconSize: 13,
              onPressed: () => Clipboard.setData(ClipboardData(text: info.hash)),
            ),
          ]),
          const SizedBox(height: 4),
          Text.rich(TextSpan(children: [
            TextSpan(text: info.author),
            TextSpan(text: ' <${info.email}>', style: secondary),
            TextSpan(text: ' on ${formatFullDate(info.date)}', style: secondary),
          ])),
          if (d.committer != info.author)
            Text('committed by ${d.committer} on ${formatFullDate(d.commitDate)}',
                style: secondary),
          if (info.refs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              runSpacing: 4,
              children: [for (final r in info.refs) RefLabelChip(label: r)],
            ),
          ],
          if (info.parents.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              Text(info.parents.length > 1 ? 'Parents:' : 'Parent:', style: secondary),
              for (final p in info.parents)
                GestureDetector(
                  onTap: () => ctrl.reveal(p),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(p.substring(0, 8),
                        style: monoStyle(context, size: 12, color: c.accent)
                            .copyWith(decoration: TextDecoration.underline)),
                  ),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
