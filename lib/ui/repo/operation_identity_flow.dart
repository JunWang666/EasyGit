import 'package:flutter/material.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../hosting/hosting.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

class CommitOperationChoice {
  const CommitOperationChoice({
    required this.name,
    required this.email,
    this.accountId,
  });

  final String name;
  final String email;
  final String? accountId;
}

Future<CommitOperationChoice?> showCommitOperationDialog(
  BuildContext context,
  RepoController ctrl, {
  required bool andPush,
}) async {
  final identity = await ctrl.repo.identity();
  if (!context.mounted) return null;
  return showDialog<CommitOperationChoice>(
    context: context,
    builder: (context) => CommitOperationDialog(
      ctrl: ctrl,
      identity: identity,
      andPush: andPush,
    ),
  );
}

class PushAccountChoice {
  const PushAccountChoice(this.account);

  final HostingAccount? account;
}

Future<void> pushFlow(
  BuildContext context,
  RepoController ctrl, {
  bool force = false,
  GitRef? branch,
}) async {
  final choice = await showPushAccountDialog(context, ctrl, branch: branch);
  if (choice == null || !context.mounted) return;
  if (branch == null) {
    await ctrl.push(force: force, account: choice.account);
  } else {
    await ctrl.pushBranch(branch, account: choice.account);
  }
}

Future<void> createRequestFlow(
  BuildContext context,
  RepoController ctrl,
  GitRef branch,
) async {
  if (branch.upstream != null) {
    await ctrl.createRequest(branch);
    return;
  }
  final choice = await showPushAccountDialog(context, ctrl, branch: branch);
  if (choice == null || !context.mounted) return;
  await ctrl.createRequest(branch, account: choice.account);
}

const _automaticAccount = '';

Future<PushAccountChoice?> showPushAccountDialog(
  BuildContext context,
  RepoController ctrl, {
  GitRef? branch,
}) async {
  final host = _remoteHost(ctrl);
  final id = await showChoiceDialog<String>(
    context,
    title: branch == null ? 'Push' : 'Push ${branch.name}',
    message: 'Choose the account used to authenticate this push.',
    initial: ctrl.account?.id ?? _automaticAccount,
    okLabel: 'Push',
    options: [
      ChoiceOption(
        _automaticAccount,
        'Automatic',
        'Use the repository default${host == null ? '' : ' for $host'}.',
      ),
      for (final account in ctrl.accounts.accounts)
        ChoiceOption(
          account.id,
          account.username,
          _accountDescription(account, host),
        ),
    ],
  );
  if (id == null) return null;
  final account = id == _automaticAccount
      ? null
      : ctrl.accounts.accounts.where((a) => a.id == id).firstOrNull;
  return PushAccountChoice(account);
}

String? _remoteHost(RepoController ctrl) {
  final remote = ctrl.primaryRemote;
  final url = remote == null ? null : ctrl.remoteUrls[remote];
  if (url == null || RegExp(r'^([A-Za-z]:[\\/]|[\\/]|file:)').hasMatch(url)) {
    return null;
  }
  return RemoteLocation.parse(url)?.host;
}

String _accountDescription(HostingAccount account, String? host) {
  final mismatch =
      host != null && account.host.toLowerCase() != host.toLowerCase();
  return '${account.server}${mismatch ? ' - not the remote server' : ''}';
}

class CommitOperationDialog extends StatefulWidget {
  const CommitOperationDialog({
    required this.ctrl,
    required this.identity,
    required this.andPush,
  });

  final RepoController ctrl;
  final RepoIdentity identity;
  final bool andPush;

  @override
  State<CommitOperationDialog> createState() => _CommitOperationDialogState();
}

class _CommitOperationDialogState extends State<CommitOperationDialog> {
  late final _name = TextEditingController(text: widget.identity.name ?? '');
  late final _email = TextEditingController(text: widget.identity.email ?? '');
  late String? _accountId = widget.ctrl.account?.id;
  String? _error;

  RepoController get ctrl => widget.ctrl;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || email.isEmpty) {
      setState(() =>
          _error = 'Enter both a name and an email for the commit identity.');
      return;
    }
    Navigator.pop(
      context,
      CommitOperationChoice(name: name, email: email, accountId: _accountId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final host = _remoteHost(ctrl);
    return IdeDialog(
      title: widget.andPush ? 'Commit and Push' : 'Commit',
      width: 560,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Commit identity',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Used as both author and committer for this commit only. '
              'Repository Settings controls the default.',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _IdentityField(
                  key: const Key('commit-identity-name'),
                  label: 'Name',
                  controller: _name,
                  autofocus: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _IdentityField(
                  key: const Key('commit-identity-email'),
                  label: 'Email',
                  controller: _email,
                  onSubmitted: _submit,
                ),
              ),
            ]),
            if (widget.andPush) ...[
              const SizedBox(height: 18),
              const Text('Push account',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              _AccountChoice(
                selected: _accountId == null,
                title: 'Automatic',
                subtitle:
                    'Use the repository default${host == null ? '' : ' for $host'}.',
                onTap: () => setState(() => _accountId = null),
              ),
              for (final account in ctrl.accounts.accounts)
                _AccountChoice(
                  selected: _accountId == account.id,
                  icon: hostingIcon(account.kind),
                  title: account.username,
                  subtitle: _accountDescription(account, host),
                  warn: host != null &&
                      account.host.toLowerCase() != host.toLowerCase(),
                  onTap: () => setState(() => _accountId = account.id),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: c.error)),
            ],
          ],
        ),
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(
          label: widget.andPush ? 'Commit and Push' : 'Commit',
          primary: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _IdentityField extends StatelessWidget {
  const _IdentityField({
    super.key,
    required this.label,
    required this.controller,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      IdeTextField(
        controller: controller,
        hint: label,
        autofocus: autofocus,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      ),
    ]);
  }
}

class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.warn = false,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData? icon;
  final bool warn;

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
                    Text(
                      subtitle,
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
