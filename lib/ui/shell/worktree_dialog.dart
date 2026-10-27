import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

typedef WorktreeRequest = ({String path, String commitish, String? newBranch, bool open});

/// Dialog for `git worktree add`. [initialBranch] preselects an existing branch.
Future<WorktreeRequest?> showAddWorktreeDialog(BuildContext context, RepoController ctrl,
        {String? initialBranch}) =>
    showDialog<WorktreeRequest>(
      context: context,
      builder: (context) => _AddWorktreeDialog(ctrl: ctrl, initialBranch: initialBranch),
    );

class _AddWorktreeDialog extends StatefulWidget {
  const _AddWorktreeDialog({required this.ctrl, this.initialBranch});

  final RepoController ctrl;
  final String? initialBranch;

  @override
  State<_AddWorktreeDialog> createState() => _AddWorktreeDialogState();
}

class _AddWorktreeDialogState extends State<_AddWorktreeDialog> {
  late final _branch = TextEditingController(text: widget.initialBranch ?? '');
  late final _base = TextEditingController(text: widget.ctrl.currentBranchLabel);
  final _path = TextEditingController();
  late var _createBranch = widget.initialBranch == null;
  var _open = true;
  var _pathEdited = false;
  String? _error;

  /// Branches already checked out in some worktree cannot be used again.
  Set<String> get _busyBranches => {
        for (final w in widget.ctrl.worktrees)
          if (w.branch != null) w.branch!,
      };

  @override
  void initState() {
    super.initState();
    _suggestPath();
  }

  @override
  void dispose() {
    _branch.dispose();
    _base.dispose();
    _path.dispose();
    super.dispose();
  }

  void _suggestPath() {
    if (_pathEdited) return;
    final root = widget.ctrl.repo.root.replaceAll('\\', '/');
    final slash = root.lastIndexOf('/');
    final parent = slash <= 0 ? root : root.substring(0, slash);
    final name = root.substring(slash + 1);
    final branch = _branch.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    _path.text = '$parent/$name${branch.isEmpty ? '-worktree' : '-$branch'}';
  }

  Future<void> _browse() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Worktree location');
    if (dir == null) return;
    setState(() {
      _pathEdited = true;
      final branch = _branch.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
      _path.text = '${dir.replaceAll('\\', '/')}/${branch.isEmpty ? 'worktree' : branch}';
    });
  }

  void _submit() {
    final branch = _branch.text.trim();
    final path = _path.text.trim();
    if (branch.isEmpty || path.isEmpty) {
      setState(() => _error = 'Enter a branch and a location.');
      return;
    }
    final exists = widget.ctrl.localBranches.any((b) => b.name == branch);
    if (_createBranch && exists) {
      setState(() => _error = 'Branch "$branch" already exists. Untick "Create new branch" to use it.');
      return;
    }
    if (!_createBranch && !exists) {
      setState(() => _error = 'Branch "$branch" does not exist.');
      return;
    }
    if (!_createBranch && _busyBranches.contains(branch)) {
      setState(() => _error = 'Branch "$branch" is already checked out in another worktree.');
      return;
    }
    Navigator.pop(context, (
      path: path,
      commitish: _createBranch ? (_base.text.trim().isEmpty ? 'HEAD' : _base.text.trim()) : branch,
      newBranch: _createBranch ? branch : null,
      open: _open,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final free = widget.ctrl.localBranches.where((b) => !_busyBranches.contains(b.name)).toList();
    return IdeDialog(
      title: 'Add Worktree',
      width: 540,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A worktree is a second checkout of this repository in another folder, so you can '
            'work on two branches at once.',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          const Text('Branch:'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: IdeTextField(
                controller: _branch,
                autofocus: true,
                hint: _createBranch ? 'new-branch-name' : 'existing branch',
                onChanged: (_) => setState(_suggestPath),
              ),
            ),
            if (!_createBranch && free.isNotEmpty)
              Builder(
                builder: (context) => IdeIconButton(
                  icon: Icons.expand_more,
                  tooltip: 'Choose branch',
                  onPressed: () async {
                    final box = context.findRenderObject()! as RenderBox;
                    final pos = box.localToGlobal(Offset(0, box.size.height));
                    final picked = await showMenu<String>(
                      context: context,
                      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
                      items: [
                        for (final b in free)
                          PopupMenuItem(value: b.name, height: 28, child: Text(b.name)),
                      ],
                    );
                    if (picked != null) {
                      setState(() {
                        _branch.text = picked;
                        _suggestPath();
                      });
                    }
                  },
                ),
              ),
          ]),
          const SizedBox(height: 8),
          _check('Create new branch', _createBranch, (v) => setState(() => _createBranch = v)),
          if (_createBranch) ...[
            const SizedBox(height: 6),
            Row(children: [
              const SizedBox(width: 26),
              const Text('from'),
              const SizedBox(width: 8),
              Expanded(child: IdeTextField(controller: _base, hint: 'HEAD')),
            ]),
          ],
          const SizedBox(height: 12),
          const Text('Location:'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: IdeTextField(controller: _path, onChanged: (_) => _pathEdited = true),
            ),
            const SizedBox(width: 6),
            IdeIconButton(icon: Icons.folder_open_outlined, tooltip: 'Browse', onPressed: _browse),
          ]),
          const SizedBox(height: 8),
          _check('Add to sidebar and open', _open, (v) => setState(() => _open = v)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: c.error)),
          ],
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Create', primary: true, onPressed: _submit),
      ],
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    final c = IdeColors.of(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
              value: value, activeColor: c.accent, onChanged: (v) => onChanged(v ?? false)),
        ),
        const SizedBox(width: 4),
        Text(label),
      ]),
    );
  }
}

/// Whether [w] is the checkout that [ctrl] has open.
bool isCurrentWorktree(RepoController ctrl, WorktreeInfo w) =>
    ReposState.samePath(w.path, ctrl.repo.root);
