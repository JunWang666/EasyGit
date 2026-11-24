import 'package:flutter/material.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../hosting/hosting.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/common.dart';

/// Defaults used by the commit, fetch, pull and push operations of one repository.
class RepoSettingsView extends StatefulWidget {
  const RepoSettingsView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  State<RepoSettingsView> createState() => _RepoSettingsViewState();
}

class _RepoSettingsViewState extends State<RepoSettingsView> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  RepoIdentity? _identity;
  var _ownIdentity = false;
  String? _accountId;
  var _saving = false;
  var _saved = false;
  String? _error;

  RepoController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _accountId = ctrl.account?.id;
    _load();
  }

  Future<void> _load() async {
    final identity = await ctrl.repo.identity();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _ownIdentity = identity.hasLocal;
      _name.text = identity.name ?? '';
      _email.text = identity.email ?? '';
      _accountId = ctrl.account?.id;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  String? get _remoteHost {
    final remote = ctrl.primaryRemote;
    final url = remote == null ? null : ctrl.remoteUrls[remote];
    if (url == null || RegExp(r'^([A-Za-z]:[\\/]|[\\/]|file:)').hasMatch(url)) {
      return null;
    }
    return RemoteLocation.parse(url)?.host;
  }

  void _changed() {
    _saved = false;
    _error = null;
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (_ownIdentity && (name.isEmpty || email.isEmpty)) {
      setState(() {
        _error = 'Enter both a name and an email for the repository identity.';
        _saved = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _saved = false;
      _error = null;
    });
    try {
      await ctrl.repo.setLocalIdentity(
          _ownIdentity ? name : null, _ownIdentity ? email : null);
      if (_accountId != ctrl.accountId) await ctrl.setAccount(_accountId);
      if (!mounted) return;
      final previous = _identity;
      setState(() {
        _identity = RepoIdentity(
          localName: _ownIdentity ? name : null,
          localEmail: _ownIdentity ? email : null,
          globalName: previous?.globalName,
          globalEmail: previous?.globalEmail,
        );
        _saving = false;
        _saved = true;
      });
    } on GitException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final identity = _identity;
    if (identity == null) {
      return Container(
          color: c.editorBg,
          child: const Center(child: CircularProgressIndicator()));
    }
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, ctrl.accounts]),
      builder: (context, _) {
        final global = identity.globalName == null &&
                identity.globalEmail == null
            ? 'not set'
            : '${identity.globalName ?? '?'} <${identity.globalEmail ?? '?'}>';
        final host = _remoteHost;
        final accounts = ctrl.accounts.accounts;
        return Container(
          color: c.editorBg,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Repository Settings',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(ctrl.name, style: TextStyle(color: c.textSecondary)),
                      const SizedBox(height: 18),
                      Text(
                        'These are the defaults for this repository. Commit and push dialogs start '
                        'with these values, and you can still choose a different identity for one operation.',
                        style: TextStyle(color: c.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      const _Label('Default commit identity'),
                      _Choice(
                        selected: !_ownIdentity,
                        title: 'Use the global identity',
                        subtitle: global,
                        onTap: () => setState(() {
                          _ownIdentity = false;
                          _changed();
                        }),
                      ),
                      _Choice(
                        selected: _ownIdentity,
                        title: 'Use a separate identity for this repository',
                        subtitle:
                            'Saved as user.name and user.email in this repository\'s .git/config.',
                        onTap: () => setState(() {
                          _ownIdentity = true;
                          _changed();
                        }),
                      ),
                      if (_ownIdentity)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(26, 8, 0, 0),
                          child: Row(children: [
                            Expanded(
                                child: IdeTextField(
                                    controller: _name, hint: 'Name')),
                            const SizedBox(width: 8),
                            Expanded(
                                child: IdeTextField(
                                    controller: _email, hint: 'Email')),
                          ]),
                        ),
                      const SizedBox(height: 24),
                      const _Label('Default fetch and push account'),
                      _Choice(
                        selected: _accountId == null,
                        title: 'Automatic',
                        subtitle:
                            'The first account signed in for the remote\'s server'
                            '${host == null ? '' : ' ($host)'}. System Git credential helpers are not used.',
                        onTap: () => setState(() {
                          _accountId = null;
                          _changed();
                        }),
                      ),
                      for (final account in accounts)
                        _Choice(
                          selected: _accountId == account.id,
                          icon: hostingIcon(account.kind),
                          title: account.username,
                          subtitle: host != null &&
                                  account.host.toLowerCase() !=
                                      host.toLowerCase()
                              ? '${account.server} - not the server of this repository\'s remote'
                              : account.server,
                          warn: host != null &&
                              account.host.toLowerCase() != host.toLowerCase(),
                          onTap: () => setState(() {
                            _accountId = account.id;
                            _changed();
                          }),
                        ),
                      if (accounts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Add accounts in Settings > Accounts to choose one here.',
                            style:
                                TextStyle(fontSize: 12, color: c.textSecondary),
                          ),
                        ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: TextStyle(color: c.error)),
                      ],
                      const SizedBox(height: 20),
                      Row(children: [
                        IdeButton(
                          label: _saving ? 'Saving...' : 'Save Defaults',
                          primary: true,
                          onPressed: _saving ? null : _save,
                        ),
                        if (_saved) ...[
                          const SizedBox(width: 10),
                          Icon(Icons.check_circle_outline,
                              size: 16, color: c.success),
                          const SizedBox(width: 5),
                          Text('Defaults saved',
                              style: TextStyle(color: c.success)),
                        ],
                      ]),
                    ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
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
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? c.accent : c.buttonBorder,
            ),
            const SizedBox(width: 8),
            if (icon != null) ...[
              Icon(icon, size: 16, color: c.icon),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                            fontSize: 12,
                            color: warn ? c.warning : c.textSecondary),
                      ),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }
}
