import 'package:flutter/material.dart';

import '../../hosting/hosting.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// "Git Remotes": list, add, edit and remove remotes of the repository.
Future<void> showManageRemotesDialog(BuildContext context, RepoController ctrl) =>
    showDialog<void>(context: context, builder: (context) => _RemotesDialog(ctrl: ctrl));

class _RemotesDialog extends StatelessWidget {
  const _RemotesDialog({required this.ctrl});

  final RepoController ctrl;

  Future<void> _edit(BuildContext context, {String? name}) async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _RemoteEditor(
        name: name ?? (ctrl.remoteUrls.isEmpty ? 'origin' : ''),
        url: name == null ? '' : ctrl.remoteUrls[name] ?? '',
        isNew: name == null,
      ),
    );
    if (result == null) return;
    final (newName, url) = result;
    if (name == null) {
      await ctrl.addRemote(newName, url);
    } else {
      await ctrl.editRemote(name, newName, url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final remotes = ctrl.remoteUrls;
        return IdeDialog(
          title: 'Git Remotes',
          width: 600,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                IdeIconButton(icon: Icons.add, tooltip: 'Add Remote', onPressed: () => _edit(context)),
              ]),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(minHeight: 120, maxHeight: 280),
                decoration: BoxDecoration(
                  color: c.editorBg,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: remotes.isEmpty
                    ? const EmptyHint(
                        'No remotes. Add one to push this repository to GitHub, GitLab or another server.')
                    : ListView(shrinkWrap: true, children: [
                        for (final e in remotes.entries) _row(context, e.key, e.value),
                      ]),
              ),
            ],
          ),
          actions: [
            IdeButton(label: 'Close', primary: true, onPressed: () => Navigator.pop(context)),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, String name, String url) {
    final c = IdeColors.of(context);
    final web = RepoWeb.forRemote(url, ctrl.accounts.accounts);
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Icon(web == null ? Icons.cloud_outlined : hostingIcon(web.kind), size: 16, color: c.icon),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12, color: c.textSecondary)),
        ),
        if (web != null)
          IdeIconButton(
            icon: Icons.open_in_new,
            tooltip: 'Open on ${web.kind.shortLabel}',
            onPressed: () => ctrl.openUrl(web.home),
          ),
        IdeIconButton(
            icon: Icons.edit_outlined, tooltip: 'Edit', onPressed: () => _edit(context, name: name)),
        IdeIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Remove',
          onPressed: () async {
            final ok = await showConfirmDialog(context,
                title: 'Remove Remote',
                message: 'Remove remote "$name"?\n\nIts remote-tracking branches are deleted too.',
                okLabel: 'Remove');
            if (ok) await ctrl.removeRemote(name);
          },
        ),
      ]),
    );
  }
}

class _RemoteEditor extends StatefulWidget {
  const _RemoteEditor({required this.name, required this.url, required this.isNew});

  final String name;
  final String url;
  final bool isNew;

  @override
  State<_RemoteEditor> createState() => _RemoteEditorState();
}

class _RemoteEditorState extends State<_RemoteEditor> {
  late final _name = TextEditingController(text: widget.name);
  late final _url = TextEditingController(text: widget.url);

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final url = _url.text.trim();
    if (name.isEmpty || url.isEmpty || name.contains(' ')) return;
    Navigator.pop(context, (name, url));
  }

  @override
  Widget build(BuildContext context) {
    return IdeDialog(
      title: widget.isNew ? 'Define Remote' : 'Edit Remote',
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Name:'),
          const SizedBox(height: 6),
          IdeTextField(controller: _name, autofocus: widget.isNew && widget.name.isEmpty),
          const SizedBox(height: 12),
          const Text('URL:'),
          const SizedBox(height: 6),
          IdeTextField(
            controller: _url,
            autofocus: !(widget.isNew && widget.name.isEmpty),
            hint: 'https://github.com/user/repo.git or git@github.com:user/repo.git',
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'OK', primary: true, onPressed: _submit),
      ],
    );
  }
}
