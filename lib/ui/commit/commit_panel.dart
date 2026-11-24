import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../repo/operation_identity_flow.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';
import 'commit_flow.dart';

/// The "Commit" tool window: changes tree with checkboxes and message box.
class CommitPanel extends StatefulWidget {
  const CommitPanel({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  State<CommitPanel> createState() => _CommitPanelState();
}

class _CommitPanelState extends State<CommitPanel> {
  final _selected = <String>{};
  final _collapsed = <String>{};
  final _focus = FocusNode();
  String? _anchor;
  bool _folderView = false;

  RepoController get ctrl => widget.ctrl;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  List<FileChange> get _selectedChanges => (ctrl.status?.changes ?? const [])
      .where((c) => _selected.contains(c.path))
      .toList();

  void _onRowTap(FileChange change, List<FileChange> ordered) {
    _focus.requestFocus();
    final keys = HardwareKeyboard.instance;
    setState(() {
      if (keys.isShiftPressed && _anchor != null) {
        final a = ordered.indexWhere((c) => c.path == _anchor);
        final b = ordered.indexOf(change);
        if (a >= 0 && b >= 0) {
          _selected
            ..clear()
            ..addAll(ordered
                .sublist(a < b ? a : b, (a < b ? b : a) + 1)
                .map((c) => c.path));
          return;
        }
      }
      if (keys.isControlPressed || keys.isMetaPressed) {
        _selected.contains(change.path)
            ? _selected.remove(change.path)
            : _selected.add(change.path);
      } else {
        _selected
          ..clear()
          ..add(change.path);
      }
      _anchor = change.path;
    });
    if (_selected.length == 1) ctrl.openWorkingDiff(change);
  }

  /// Moves a single selection up or down and shows that file's diff.
  void _moveSelection(List<FileChange> ordered, int delta) {
    if (ordered.isEmpty) return;
    final currentPath = _anchor ?? ctrl.changesDiff?.change.path;
    final index = ordered.indexWhere((c) => c.path == currentPath);
    final next =
        ordered[(index < 0 ? 0 : index + delta).clamp(0, ordered.length - 1)];
    setState(() {
      _selected
        ..clear()
        ..add(next.path);
      _anchor = next.path;
    });
    ctrl.openWorkingDiff(next);
  }

  Future<void> _rollback(List<FileChange> files) async {
    final tracked = files.where((f) => !f.isUntracked).toList();
    if (tracked.isEmpty) return;
    final list = tracked.take(10).map((f) => '  ${f.path}').join('\n');
    final more =
        tracked.length > 10 ? '\n  ...and ${tracked.length - 10} more' : '';
    final ok = await showConfirmDialog(context,
        title: 'Rollback Changes',
        message:
            'Local changes in these files will be discarded:\n\n$list$more',
        okLabel: 'Rollback');
    if (ok) await ctrl.rollback(tracked);
  }

  Future<void> _stash() async {
    final message = await showInputDialog(context,
        title: 'Stash Changes',
        label: 'Message (optional):',
        initial: 'WIP',
        okLabel: 'Stash');
    if (message != null) await ctrl.stash(message);
  }

  void _contextMenu(Offset position, FileChange change) {
    if (!_selected.contains(change.path)) {
      setState(() {
        _selected
          ..clear()
          ..add(change.path);
        _anchor = change.path;
      });
    }
    final files = _selectedChanges;
    final c = IdeColors.of(context);
    showIdeMenu(context, position, [
      IdeMenuItem('Show Diff',
          icon: Icons.compare_arrows,
          shortcut: shortcutLabel('D'),
          onTap: () => ctrl.openWorkingDiff(change)),
      const IdeMenuItem.divider(),
      if (files.any((f) => f.isUntracked))
        IdeMenuItem('Add to VCS',
            icon: Icons.add,
            iconColor: c.success,
            onTap: () =>
                ctrl.addToVcs(files.where((f) => f.isUntracked).toList())),
      IdeMenuItem('Rollback...',
          icon: Icons.undo,
          enabled: files.any((f) => !f.isUntracked),
          onTap: () => _rollback(files)),
      const IdeMenuItem.divider(),
      IdeMenuItem('Copy Path',
          icon: Icons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: change.path))),
      IdeMenuItem('Copy Absolute Path',
          onTap: () => Clipboard.setData(
              ClipboardData(text: '${ctrl.repo.root}/${change.path}'))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final tracked = ctrl.trackedChanges;
        final untracked = ctrl.untrackedChanges;
        final selected = _selectedChanges;
        return Column(children: [
          PanelHeader(
            title: 'Local Changes',
            trailing: Row(children: [
              IdeIconButton(
                icon: Icons.info_outline,
                tooltip: ctrl.showWorkingFileDetails
                    ? 'Hide File Size and Modified Time'
                    : 'Show File Size and Modified Time',
                selected: ctrl.showWorkingFileDetails,
                onPressed: () => ctrl
                    .setShowWorkingFileDetails(!ctrl.showWorkingFileDetails),
              ),
              IdeIconButton(
                icon: Icons.account_tree_outlined,
                tooltip: _folderView ? 'Show Flat List' : 'Show Folder Tree',
                selected: _folderView,
                onPressed: () => setState(() => _folderView = !_folderView),
              ),
              IdeIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Refresh',
                  onPressed: ctrl.refreshAll),
              IdeIconButton(
                icon: Icons.undo,
                tooltip: 'Rollback...',
                onPressed: selected.any((f) => !f.isUntracked)
                    ? () => _rollback(selected)
                    : null,
              ),
              IdeIconButton(
                icon: Icons.inventory_2_outlined,
                tooltip: 'Stash Changes...',
                onPressed: tracked.isEmpty && untracked.isEmpty ? null : _stash,
              ),
              IdeIconButton(
                  icon: Icons.unarchive_outlined,
                  tooltip: 'Unstash (pop latest stash)',
                  onPressed: ctrl.stashes.isEmpty ? null : ctrl.stashPop),
            ]),
          ),
          Expanded(
            child: ctrl.commitMessageCollapsed
                ? Column(children: [
                    Expanded(child: _changesTree(tracked, untracked)),
                    _messageArea(),
                  ])
                : SplitPane(
                    axis: Axis.vertical,
                    sizeOfSecond: true,
                    initialSize: 200,
                    minSize: 120,
                    minOther: 80,
                    first: _changesTree(tracked, untracked),
                    second: _messageArea(),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _changesTree(List<FileChange> tracked, List<FileChange> untracked) {
    if (ctrl.status == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (tracked.isEmpty && untracked.isEmpty) {
      return const EmptyHint('No local changes');
    }
    final ordered = <FileChange>[];
    List<Widget> rows() {
      ordered.clear();
      return [
        if (tracked.isNotEmpty) ...[
          _groupRow('changes', 'Changes', tracked),
          if (!_collapsed.contains('changes'))
            ..._fileRows('changes', tracked, ordered),
        ],
        if (untracked.isNotEmpty) ...[
          _groupRow('unversioned', 'Unversioned Files', untracked),
          if (!_collapsed.contains('unversioned'))
            ..._fileRows('unversioned', untracked, ordered),
        ],
      ];
    }

    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveSelection(ordered, 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveSelection(ordered, -1);
          return KeyEventResult.handled;
        }
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.space &&
            _selected.isNotEmpty) {
          final changes = _selectedChanges;
          final include = !changes.every((c) => ctrl.included.contains(c.path));
          ctrl.setIncluded(changes, include);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            _selected.length == 1) {
          ctrl.openWorkingDiff(_selectedChanges.first);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ListenableBuilder(
        listenable: _focus,
        builder: (context, _) => ListView(children: rows()),
      ),
    );
  }

  Widget _groupRow(String id, String title, List<FileChange> files) {
    final c = IdeColors.of(context);
    final count = files.where((f) => ctrl.included.contains(f.path)).length;
    final value = count == 0 ? false : (count == files.length ? true : null);
    final collapsed = _collapsed.contains(id);
    return ListRow(
      onTap: () => setState(
          () => collapsed ? _collapsed.remove(id) : _collapsed.add(id)),
      child: Row(children: [
        Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 16, color: c.icon),
        _checkbox(value, (v) => ctrl.setIncluded(files, v ?? false),
            tristate: true),
        const SizedBox(width: 4),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('${files.length} file${files.length == 1 ? '' : 's'}',
            style: TextStyle(color: c.textSecondary)),
      ]),
    );
  }

  List<Widget> _fileRows(
      String groupId, List<FileChange> files, List<FileChange> ordered) {
    if (!_folderView) {
      return [for (final f in files) _fileRow(f, ordered)];
    }
    return _folderContents(groupId, '', files, 1, ordered);
  }

  List<Widget> _folderContents(String groupId, String path,
      List<FileChange> files, int depth, List<FileChange> ordered) {
    final direct = <FileChange>[];
    final folders = <String, List<FileChange>>{};
    for (final file in files) {
      final relative =
          path.isEmpty ? file.path : file.path.substring(path.length + 1);
      final slash = relative.indexOf('/');
      if (slash < 0) {
        direct.add(file);
      } else {
        folders.putIfAbsent(relative.substring(0, slash), () => []).add(file);
      }
    }
    final folderNames = folders.keys.toList()..sort();
    return [
      for (final name in folderNames) ...[
        _folderRow(groupId, path.isEmpty ? name : '$path/$name', name,
            folders[name]!, depth),
        if (!_collapsed
            .contains('folder:$groupId:${path.isEmpty ? name : '$path/$name'}'))
          ..._folderContents(groupId, path.isEmpty ? name : '$path/$name',
              folders[name]!, depth + 1, ordered),
      ],
      for (final file in direct)
        _fileRow(file, ordered, depth: depth, folderView: true),
    ];
  }

  Widget _folderRow(String groupId, String path, String name,
      List<FileChange> files, int depth) {
    final c = IdeColors.of(context);
    final id = 'folder:$groupId:$path';
    final collapsed = _collapsed.contains(id);
    final count = files.where((f) => ctrl.included.contains(f.path)).length;
    final value = count == 0 ? false : (count == files.length ? true : null);
    return ListRow(
      key: ValueKey(id),
      indent: depth * 18,
      onTap: () => setState(
          () => collapsed ? _collapsed.remove(id) : _collapsed.add(id)),
      child: Row(children: [
        Icon(collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 16, color: c.icon),
        _checkbox(value, (v) => ctrl.setIncluded(files, v ?? false),
            tristate: true),
        const SizedBox(width: 4),
        Icon(collapsed ? Icons.folder_outlined : Icons.folder_open_outlined,
            size: 16, color: c.icon),
        const SizedBox(width: 6),
        Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Text('${files.length}',
            style: TextStyle(fontSize: 11, color: c.textSecondary)),
      ]),
    );
  }

  Widget _fileRow(FileChange f, List<FileChange> ordered,
      {int depth = 1, bool folderView = false}) {
    ordered.add(f);
    final c = IdeColors.of(context);
    final info = ctrl.workingFileInfo[f.path];
    final detailStyle = TextStyle(fontSize: 11, color: c.textSecondary);
    return ListRow(
      indent: depth * 18,
      selected: _selected.contains(f.path) ||
          (_selected.isEmpty && ctrl.changesDiff?.change.path == f.path),
      focused: _focus.hasFocus,
      onTap: () => _onRowTap(f, ordered),
      onContextMenu: (pos) => _contextMenu(pos, f),
      child: Row(children: [
        if (folderView) const SizedBox(width: 16),
        _checkbox(ctrl.included.contains(f.path),
            (v) => ctrl.toggleIncluded(f.path, v ?? false)),
        const SizedBox(width: 4),
        Expanded(
            child: FileChangeLabel(
                change: f,
                showDirectory: !folderView,
                lfs: ctrl.lfs.isTracked(f.path))),
        if (ctrl.showWorkingFileDetails) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(info == null ? '—' : formatBytes(info.size),
                textAlign: TextAlign.right, maxLines: 1, style: detailStyle),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 112,
            child: Tooltip(
              message: info == null
                  ? 'File is not present in the working tree'
                  : formatFullDate(info.modified),
              child: Text(
                info == null ? '—' : formatLogDate(info.modified),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: detailStyle,
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _checkbox(bool? value, ValueChanged<bool?> onChanged,
      {bool tristate = false}) {
    final c = IdeColors.of(context);
    return SizedBox(
      width: 22,
      height: 22,
      child: Checkbox(
        value: value,
        tristate: tristate,
        activeColor: c.accent,
        onChanged: (v) => onChanged(tristate && value == null ? true : v),
      ),
    );
  }

  Widget _messageArea() {
    final c = IdeColors.of(context);
    final busy = ctrl.busy != null;
    final collapsed = ctrl.commitMessageCollapsed;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: c.panelBg,
        border: collapsed ? Border(top: BorderSide(color: c.splitter)) : null,
      ),
      child: Column(
        mainAxisSize: collapsed ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IdeIconButton(
              icon: collapsed ? Icons.chevron_right : Icons.expand_more,
              tooltip: collapsed
                  ? 'Expand Commit Message'
                  : 'Collapse Commit Message',
              size: 22,
              onPressed: () => ctrl.setCommitMessageCollapsed(!collapsed),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text('Commit Message',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: ctrl.amend,
                activeColor: c.accent,
                onChanged: (v) => ctrl.setAmend(v ?? false),
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => ctrl.setAmend(!ctrl.amend),
              child: const Text('Amend'),
            ),
          ]),
          if (!collapsed) ...[
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: c.editorBg,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: c.border),
                ),
                child: TextField(
                  controller: ctrl.messageController,
                  focusNode: ctrl.messageFocus,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: monoStyle(context),
                  decoration: InputDecoration(
                    hintText: 'Commit Message',
                    hintStyle: monoStyle(context, color: c.textSecondary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(8),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            IdeButton(
              label: ctrl.amend ? 'Amend Commit' : 'Commit',
              primary: true,
              onPressed: busy
                  ? null
                  : () => commitFlow(context, ctrl,
                      identity: ctrl.selectedCommitIdentity),
            ),
            _identityButton(busy),
            IdeButton(
              label: ctrl.amend ? 'Amend and Push...' : 'Commit and Push...',
              onPressed: busy
                  ? null
                  : () => commitFlow(context, ctrl,
                      andPush: true, identity: ctrl.selectedCommitIdentity),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _identityButton(bool busy) {
    final c = IdeColors.of(context);
    final identity = ctrl.selectedCommitIdentity;
    final label =
        identity?.name?.isNotEmpty == true ? identity!.name! : 'Set Identity';
    final tooltip = identity == null
        ? 'Commit identity'
        : 'Commit identity: ${identity.name ?? '?'} <${identity.email ?? '?'}>';
    return Builder(
      builder: (buttonContext) => HoverBuilder(
        cursor: busy ? MouseCursor.defer : SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          key: const Key('commit-identity-selector'),
          onTap: busy ? null : () => _showIdentityMenu(buttonContext),
          child: Tooltip(
            message: tooltip,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: hovered && !busy ? c.hover : Colors.transparent,
                border: Border.all(color: c.buttonBorder),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_outline,
                    size: 15, color: busy ? c.textDisabled : c.textSecondary),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: busy ? c.textDisabled : c.text)),
                ),
                const SizedBox(width: 3),
                Icon(Icons.arrow_drop_down,
                    size: 15, color: busy ? c.textDisabled : c.textSecondary),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showIdentityMenu(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject()! as RenderBox;
    final position = box.localToGlobal(Offset(0, box.size.height));
    final defaultIdentity =
        ctrl.commitIdentity ?? await ctrl.loadCommitIdentity();
    if (!buttonContext.mounted) return;
    await showIdeMenu(buttonContext, position, [
      IdeMenuItem(
        'Default: ${defaultIdentity.name ?? 'not set'}',
        icon: ctrl.commitIdentityOverride == null ? Icons.check : null,
        onTap: () => ctrl.setCommitIdentityOverride(null),
      ),
      IdeMenuItem(
        'Custom Identity...',
        icon: ctrl.commitIdentityOverride == null ? null : Icons.check,
        onTap: () => _customIdentity(defaultIdentity),
      ),
    ]);
  }

  Future<void> _customIdentity(RepoIdentity defaultIdentity) async {
    final current = ctrl.selectedCommitIdentity ?? defaultIdentity;
    final choice = await showDialog<CommitOperationChoice>(
      context: context,
      builder: (context) => CommitOperationDialog(
        ctrl: ctrl,
        identity: current,
        andPush: false,
        selectionOnly: true,
      ),
    );
    if (choice == null) return;
    ctrl.setCommitIdentityOverride(
        RepoIdentity(localName: choice.name, localEmail: choice.email));
  }
}
