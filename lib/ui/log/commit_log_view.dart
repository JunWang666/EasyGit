import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';
import 'graph_painter.dart';

const _rowHeight = 24.0;

/// The commit table of the Git Log tab: filters, graph, subject, author, date.
class CommitLogView extends StatefulWidget {
  const CommitLogView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  State<CommitLogView> createState() => _CommitLogViewState();
}

class _CommitLogViewState extends State<CommitLogView> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final _search = TextEditingController(text: widget.ctrl.textFilter);
  int _revealTick = 0;

  RepoController get ctrl => widget.ctrl;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  int get _selectedRow {
    final hash = ctrl.selectedHash;
    if (hash == null) return -1;
    return ctrl.visible.indexWhere((i) => ctrl.commits[i].hash == hash);
  }

  void _ensureVisible(int row, {bool center = false}) {
    if (row < 0 || !_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final top = row * _rowHeight;
    var target = _scroll.offset;
    if (center) {
      target = top - viewport / 2 + _rowHeight / 2;
    } else if (top < _scroll.offset) {
      target = top;
    } else if (top + _rowHeight > _scroll.offset + viewport) {
      target = top + _rowHeight - viewport;
    }
    _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final visible = ctrl.visible;
    if (visible.isEmpty) return KeyEventResult.ignored;
    var row = _selectedRow;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      row = (row + 1).clamp(0, visible.length - 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      row = (row - 1).clamp(0, visible.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown) {
      row = (row + 20).clamp(0, visible.length - 1);
    } else if (key == LogicalKeyboardKey.pageUp) {
      row = (row - 20).clamp(0, visible.length - 1);
    } else if (key == LogicalKeyboardKey.home) {
      row = 0;
    } else if (key == LogicalKeyboardKey.end) {
      row = visible.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    ctrl.selectCommit(ctrl.commits[visible[row]].hash);
    _ensureVisible(row);
    return KeyEventResult.handled;
  }

  Future<void> _commitMenu(Offset position, CommitInfo commit) async {
    ctrl.selectCommit(commit.hash);
    final c = IdeColors.of(context);
    final branch = ctrl.currentBranchLabel;
    final web = ctrl.webFor();
    await showIdeMenu(context, position, [
      IdeMenuItem('Copy Revision Number',
          icon: Icons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: commit.hash))),
      if (web != null)
        IdeMenuItem('Open on ${web.kind.shortLabel}',
            icon: hostingIcon(web.kind), onTap: () => ctrl.openUrl(web.commit(commit.hash))),
      const IdeMenuItem.divider(),
      IdeMenuItem('Cherry-Pick',
          icon: Icons.call_merge, iconColor: c.success, onTap: () => ctrl.cherryPick(commit)),
      IdeMenuItem('Checkout Revision', icon: Icons.login,
          onTap: () => ctrl.checkoutRevision(commit.hash)),
      const IdeMenuItem.divider(),
      IdeMenuItem('Reset Current Branch to Here...', icon: Icons.restore,
          onTap: () => _reset(commit, branch)),
      IdeMenuItem('Revert Commit', icon: Icons.undo, onTap: () => _revert(commit)),
      const IdeMenuItem.divider(),
      IdeMenuItem('New Branch...', icon: Icons.call_split, onTap: () => _newBranch(commit)),
      IdeMenuItem('New Tag...', icon: Icons.sell_outlined, onTap: () => _newTag(commit)),
    ]);
  }

  Future<void> _reset(CommitInfo commit, String branch) async {
    final mode = await showChoiceDialog<ResetMode>(
      context,
      title: 'Git Reset',
      message: "Reset '$branch' to ${commit.shortHash} \"${commit.subject}\"",
      initial: ResetMode.mixed,
      okLabel: 'Reset',
      options: const [
        ChoiceOption(ResetMode.soft, 'Soft',
            'Files won\'t change, differences will be staged for commit.'),
        ChoiceOption(ResetMode.mixed, 'Mixed',
            'Files won\'t change, differences won\'t be staged.'),
        ChoiceOption(ResetMode.hard, 'Hard',
            'Files will be reverted to the state of the selected commit. Local changes will be lost.'),
        ChoiceOption(ResetMode.keep, 'Keep',
            'Files will be reverted, but local changes will be kept intact.'),
      ],
    );
    if (mode != null) await ctrl.reset(commit, mode);
  }

  Future<void> _revert(CommitInfo commit) async {
    final ok = await showConfirmDialog(context,
        title: 'Revert Commit',
        message: 'Create a new commit that reverts ${commit.shortHash} "${commit.subject}"?',
        okLabel: 'Revert');
    if (ok) await ctrl.revert(commit);
  }

  Future<void> _newBranch(CommitInfo commit) async {
    final result = await showNewBranchDialog(context, commit.shortHash);
    if (result != null) {
      await ctrl.createBranch(result.name, commit.hash, checkout: result.checkout);
    }
  }

  Future<void> _newTag(CommitInfo commit) async {
    final name = await showInputDialog(context,
        title: 'Tag ${commit.shortHash}', label: 'Enter the name of new tag:', okLabel: 'Create');
    if (name != null) await ctrl.createTag(name, commit);
  }

  void _branchFilterMenu(Offset position) {
    final branch = ctrl.status?.branch;
    showIdeMenu(context, position, [
      IdeMenuItem('All', onTap: () => ctrl.setBranchFilter(null)),
      IdeMenuItem('HEAD (Current Branch)', onTap: () => ctrl.setBranchFilter('HEAD')),
      const IdeMenuItem.divider(),
      for (final r in ctrl.localBranches.take(30))
        IdeMenuItem(r.name,
            icon: r.name == branch ? Icons.local_offer : Icons.call_split,
            onTap: () => ctrl.setBranchFilter(r.name)),
      if (ctrl.remoteBranches.isNotEmpty) const IdeMenuItem.divider(),
      for (final r in ctrl.remoteBranches.take(30))
        IdeMenuItem(r.name, icon: Icons.cloud_outlined, onTap: () => ctrl.setBranchFilter(r.name)),
    ]);
  }

  void _userFilterMenu(Offset position) {
    showIdeMenu(context, position, [
      IdeMenuItem('All', onTap: () => ctrl.setAuthorFilter(null)),
      const IdeMenuItem.divider(),
      for (final a in ctrl.authors.take(30))
        IdeMenuItem(a, icon: Icons.person_outline, onTap: () => ctrl.setAuthorFilter(a)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, _focus]),
      builder: (context, _) {
        if (ctrl.revealTick != _revealTick) {
          _revealTick = ctrl.revealTick;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureVisible(_selectedRow, center: true);
            _focus.requestFocus();
          });
        }
        final visible = ctrl.visible;
        final headHash = ctrl.status?.headHash;
        var maxLanes = 1;
        if (ctrl.graphVisible) {
          for (final i in visible) {
            if (ctrl.graph[i].width > maxLanes) maxLanes = ctrl.graph[i].width;
          }
        }
        return Column(children: [
          SizedBox(
            height: 36,
            child: Row(children: [
              const SizedBox(width: 8),
              IdeTextField(
                width: 220,
                controller: _search,
                hint: 'Text or hash',
                prefixIcon: Icons.search,
                onChanged: ctrl.setTextFilter,
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Branch',
                value: ctrl.branchFilter,
                onTap: _branchFilterMenu,
                onClear: () => ctrl.setBranchFilter(null),
              ),
              _FilterChip(
                label: 'User',
                value: ctrl.authorFilter,
                onTap: _userFilterMenu,
                onClear: () => ctrl.setAuthorFilter(null),
              ),
              const Spacer(),
              if (ctrl.logLoading)
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              IdeIconButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: ctrl.refreshAll),
              const SizedBox(width: 6),
            ]),
          ),
          Container(height: 1, color: c.border),
          Expanded(
            child: visible.isEmpty
                ? EmptyHint(ctrl.logLoading
                    ? 'Loading...'
                    : (ctrl.commits.isEmpty ? 'No commits yet' : 'No commits matching filters'))
                : Focus(
                    focusNode: _focus,
                    onKeyEvent: _onKey,
                    child: Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        itemExtent: _rowHeight,
                        itemCount: visible.length,
                        itemBuilder: (context, row) {
                          final index = visible[row];
                          return _commitRow(ctrl.commits[index], index, maxLanes,
                              isHead: ctrl.commits[index].hash == headHash);
                        },
                      ),
                    ),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _commitRow(CommitInfo commit, int index, int maxLanes, {required bool isHead}) {
    final c = IdeColors.of(context);
    final selected = commit.hash == ctrl.selectedHash;
    final bg = selected ? (_focus.hasFocus ? c.selection : c.selectionInactive) : c.panelBg;
    final graphRow = ctrl.graphVisible ? ctrl.graph[index] : null;
    final secondary = TextStyle(color: c.textSecondary);
    return ListRow(
      height: _rowHeight,
      selected: selected,
      focused: _focus.hasFocus,
      onTap: () {
        _focus.requestFocus();
        ctrl.selectCommit(commit.hash);
      },
      onContextMenu: (pos) => _commitMenu(pos, commit),
      child: Row(children: [
        if (graphRow != null)
          CustomPaint(
            size: Size(graphWidth(maxLanes), _rowHeight),
            painter: GraphPainter(graphRow, c.graphColors, isHead: isHead, background: bg),
          ),
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(commit.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: isHead ? FontWeight.w600 : FontWeight.normal)),
            ),
            for (final r in commit.refs.take(3)) RefLabelChip(label: r),
            if (commit.refs.length > 3)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text('+${commit.refs.length - 3}', style: secondary),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: Text(commit.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
        ),
        SizedBox(
          width: 140,
          child: Text(formatLogDate(commit.date), maxLines: 1, style: secondary),
        ),
        SizedBox(
          width: 72,
          child: Text(commit.shortHash,
              maxLines: 1, style: monoStyle(context, size: 12, color: c.textSecondary)),
        ),
      ]),
    );
  }
}

/// Branch or tag decoration next to a commit subject.
class RefLabelChip extends StatelessWidget {
  const RefLabelChip({super.key, required this.label});

  final RefLabel label;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final (icon, color) = switch (label.type) {
      RefLabelType.head => (Icons.local_offer, c.refHead),
      RefLabelType.local => (label.isCurrent ? Icons.local_offer : Icons.call_split, c.refLocal),
      RefLabelType.remote => (Icons.cloud_outlined, c.refRemote),
      RefLabelType.tag => (Icons.sell_outlined, c.refTag),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: label.isCurrent ? c.refHead : color),
        const SizedBox(width: 3),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(label.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color)),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.value, required this.onTap, required this.onClear});

  final String label;
  final String? value;
  final void Function(Offset position) onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final active = value != null;
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTapUp: (d) => onTap(d.globalPosition),
        child: Container(
          height: 26,
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hovered ? c.hover : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(active ? '$label: ' : label, style: TextStyle(color: c.textSecondary)),
            if (active)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(value!, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
            if (active)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.close, size: 13, color: c.textSecondary),
                ),
              )
            else
              Icon(Icons.expand_more, size: 15, color: c.textSecondary),
          ]),
        ),
      ),
    );
  }
}
