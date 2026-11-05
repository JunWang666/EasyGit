import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hosting/hosting.dart';
import '../../state/accounts_store.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';

IconData hostingIcon(HostingKind kind) => switch (kind) {
      HostingKind.github => Icons.hub_outlined,
      HostingKind.gitlab => Icons.change_history,
      HostingKind.gitea => Icons.local_cafe_outlined,
      HostingKind.generic => Icons.dns_outlined,
    };

/// Adds an account of [kind]. Returns it, or null if cancelled.
Future<HostingAccount?> showAddAccountDialog(
        BuildContext context, AccountsStore store, HostingKind kind) =>
    showDialog<HostingAccount>(
      context: context,
      builder: (context) => _AddAccountDialog(store: store, kind: kind),
    );

/// Lets the user pick a provider, then adds an account for it.
Future<HostingAccount?> pickAndAddAccount(
    BuildContext context, AccountsStore store, Offset position) async {
  HostingKind? kind;
  await showIdeMenu(context, position, [
    for (final k in HostingKind.values)
      IdeMenuItem('${k.label}...', icon: hostingIcon(k), onTap: () => kind = k),
  ]);
  if (kind == null || !context.mounted) return null;
  return showAddAccountDialog(context, store, kind!);
}

/// Settings > Accounts: list, add and remove hosting accounts.
class AccountsPanel extends StatelessWidget {
  const AccountsPanel({super.key, required this.store});

  final AccountsStore store;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accounts are used to list repositories when cloning, and to authenticate '
            'fetch, pull and push over HTTPS. Tokens are kept in the system credential store.',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            constraints: BoxConstraints(
                minHeight: 120, maxHeight: store.accounts.isEmpty ? 120 : 420),
            decoration: BoxDecoration(
              color: c.editorBg,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(5),
            ),
            child: store.accounts.isEmpty
                ? const EmptyHint('No accounts. Add a GitHub, GitLab or Gitea account.')
                : ListView(shrinkWrap: true, children: [
                    for (final a in store.accounts) _accountRow(context, a),
                  ]),
          ),
          const SizedBox(height: 10),
          Builder(
            builder: (context) => HoverBuilder(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTapUp: (d) => pickAndAddAccount(context, store, d.globalPosition),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 16, color: c.accent),
                  const SizedBox(width: 4),
                  Text('Add Account',
                      style: TextStyle(
                          color: c.accent, decoration: hovered ? TextDecoration.underline : null)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountRow(BuildContext context, HostingAccount a) {
    final c = IdeColors.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Icon(hostingIcon(a.kind), size: 20, color: c.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.username, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${a.kind.label} · ${a.server}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.textSecondary)),
            ],
          ),
        ),
        if (store.tokenFor(a) == null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('Token missing', style: TextStyle(fontSize: 12, color: c.error)),
          ),
        IdeIconButton(
          icon: Icons.delete_outline,
          tooltip: 'Remove Account',
          onPressed: () async {
            final ok = await showConfirmDialog(context,
                title: 'Remove Account',
                message: 'Remove ${a.username} on ${a.server}?\n\n'
                    'The token is deleted from this computer. It stays valid on the server '
                    'until you revoke it there.',
                okLabel: 'Remove');
            if (ok) await store.remove(a);
          },
        ),
      ]),
    );
  }
}

class _AddAccountDialog extends StatefulWidget {
  const _AddAccountDialog({required this.store, required this.kind});

  final AccountsStore store;
  final HostingKind kind;

  @override
  State<_AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<_AddAccountDialog> {
  late final _server = TextEditingController(text: widget.kind.defaultServer);
  final _username = TextEditingController();
  final _token = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_server.text.trim().isEmpty || _token.text.trim().isEmpty) {
      setState(() => _error = 'Enter the server and a token.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account =
          await widget.store.add(widget.kind, _server.text, _token.text, username: _username.text);
      if (mounted) Navigator.pop(context, account);
    } on HostingException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final kind = widget.kind;
    return IdeDialog(
      title: 'Log In to ${kind.label}',
      width: 480,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!kind.hasApi) ...[
            Text(
              'For self-hosted Git or Git LFS servers (for example Gitea, GitLab, Gogs, '
              'Bitbucket Data Center, or a standalone LFS server). EasyGit gives these '
              'credentials to git and git-lfs for this server.',
              style: TextStyle(color: c.textSecondary),
            ),
            const SizedBox(height: 12),
          ],
          Text(switch (kind) {
            HostingKind.github => 'Server (github.com or your GitHub Enterprise URL):',
            HostingKind.gitlab => 'Server (gitlab.com or your self-managed GitLab URL):',
            HostingKind.gitea => 'Server (e.g. codeberg.org or your Gitea / Forgejo URL):',
            HostingKind.generic => 'Server address (e.g. https://git.example.com):',
          }),
          const SizedBox(height: 6),
          IdeTextField(controller: _server),
          if (!kind.hasApi) ...[
            const SizedBox(height: 12),
            const Text('Username:'),
            const SizedBox(height: 6),
            IdeTextField(controller: _username),
          ],
          const SizedBox(height: 12),
          Text(kind.hasApi ? 'Personal access token:' : 'Password or token:'),
          const SizedBox(height: 6),
          _TokenField(controller: _token, onSubmitted: _submit),
          const SizedBox(height: 6),
          if (!kind.hasApi)
            Text(HostingApi.tokenScopesHint(kind),
                style: TextStyle(fontSize: 12, color: c.textSecondary))
          else
            Row(children: [
              HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: () => launchUrl(Uri.parse(HostingApi.tokenPage(kind, _server.text)),
                      mode: LaunchMode.externalApplication),
                  child: Text('Generate token...',
                      style: TextStyle(
                          color: c.accent, decoration: hovered ? TextDecoration.underline : null)),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(HostingApi.tokenScopesHint(kind),
                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ),
            ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.error)),
          ],
        ],
      ),
      actions: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child:
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Log In', primary: true, onPressed: _busy ? null : _submit),
      ],
    );
  }
}

class _TokenField extends StatelessWidget {
  const _TokenField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: c.buttonBorder),
    );
    return SizedBox(
      height: 28,
      child: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => onSubmitted(),
        style: TextStyle(fontSize: 13, color: c.text),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: c.accent, width: 2)),
        ),
      ),
    );
  }
}
