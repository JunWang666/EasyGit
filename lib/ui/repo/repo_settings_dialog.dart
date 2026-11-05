import 'package:flutter/material.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../hosting/hosting.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// Commit identity and push account of one repository.
Future<void> showRepoSettingsDialog(BuildContext context, RepoController ctrl) async {
  final identity = await ctrl.repo.identity();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _RepoSettingsDialog(ctrl: ctrl, identity: identity),
  );
}

class _RepoSettingsDialog extends StatefulWidget {
  const _RepoSettingsDialog({required this.ctrl, required this.identity});

  final RepoController ctrl;
  final RepoIdentity identity;

  @override
  State<_RepoSettingsDialog> createState() => _RepoSettingsDialogState();
}

class _RepoSettingsDialogState extends State<_RepoSettingsDialog> {
  late var _ownIdentity = widget.identity.hasLocal;
  late final _name = TextEditingController(text: widget.identity.name ?? '');
  late final _email = TextEditingController(text: widget.identity.email ?? '');
  late String? _accountId = widget.ctrl.account?.id;
  String? _error;

  /// Host of the remote that fetch and push use, to point out matching accounts.
  String? get _remoteHost {
    final remote = widget.ctrl.primaryRemote;
    final url = remote == null ? null : widget.ctrl.remoteUrls[remote];
    // Local paths (C:\repo.git, /srv/repo.git, file://) have no server.
    if (url == null || RegExp(r'^([A-Za-z]:[\\/]|[\\/]|file:)').hasMatch(url)) return null;
    return RemoteLocation.parse(url)?.host;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final repo = widget.ctrl.repo;
      _ownIdentity
          ? await repo.setLocalIdentity(_name.text, _email.text)
          : await repo.setLocalIdentity(null, null);
      if (_accountId != widget.ctrl.accountId) await widget.ctrl.setAccount(_accountId);
      if (mounted) Navigator.pop(context);
    } on GitException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final id = widget.identity;
    final global = id.globalName == null && id.globalEmail == null
        ? 'not set'
        : '${id.globalName ?? '?'} <${id.globalEmail ?? '?'}>';
    final host = _remoteHost;
    final accounts = widget.ctrl.accounts.accounts;
    return IdeDialog(
      title: 'Repository Settings: ${widget.ctrl.name}',
      width: 560,
      content: SingleChildScrollView(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Label('Commit identity'),
              _Choice(
                selected: !_ownIdentity,
                title: 'Use the global identity',
                subtitle: global,
                onTap: () => setState(() => _ownIdentity = false),
              ),
              _Choice(
                selected: _ownIdentity,
                title: 'Use a separate identity for this repository',
                subtitle: 'Saved as user.name and user.email in this repository\'s .git/config, '
                    'so git on the command line uses it too.',
                onTap: () => setState(() => _ownIdentity = true),
              ),
              if (_ownIdentity)
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 6, 0, 0),
                  child: Row(children: [
                    Expanded(child: IdeTextField(controller: _name, hint: 'Name')),
                    const SizedBox(width: 8),
                    Expanded(child: IdeTextField(controller: _email, hint: 'Email')),
                  ]),
                ),
              const SizedBox(height: 18),
              const _Label('Fetch and push account'),
              _Choice(
                selected: _accountId == null,
                title: 'Automatic',
                subtitle: 'The first account signed in for the remote\'s server'
                    '${host == null ? '' : ' ($host)'}, or Git\'s own credential manager.',
                onTap: () => setState(() => _accountId = null),
              ),
              for (final a in accounts)
                _Choice(
                  selected: _accountId == a.id,
                  icon: hostingIcon(a.kind),
                  title: a.username,
                  subtitle: host != null && a.host.toLowerCase() != host.toLowerCase()
                      ? '${a.server} - not the server of this repository\'s remote'
                      : a.server,
                  warn: host != null && a.host.toLowerCase() != host.toLowerCase(),
                  onTap: () => setState(() => _accountId = a.id),
                ),
              if (accounts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Add accounts in Settings > Accounts to choose one here.',
                      style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: TextStyle(color: c.error)),
              ],
            ]),
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Save', primary: true, onPressed: _save),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.warn = false,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool warn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 16, color: selected ? c.accent : c.buttonBorder),
            const SizedBox(width: 8),
            if (icon != null) ...[
              Icon(icon, size: 16, color: c.icon),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(fontSize: 12, color: warn ? c.warning : c.textSecondary)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
