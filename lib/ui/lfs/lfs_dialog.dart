import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../git/lfs.dart';
import '../../state/lfs_credentials.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// Git LFS settings for a repository: setup, tracking and server.
Future<void> showLfsDialog(BuildContext context, RepoController ctrl) =>
    showDialog<void>(
        context: context, builder: (context) => _LfsDialog(ctrl: ctrl));

class _LfsDialog extends StatefulWidget {
  const _LfsDialog({required this.ctrl});

  final RepoController ctrl;

  @override
  State<_LfsDialog> createState() => _LfsDialogState();
}

class _LfsDialogState extends State<_LfsDialog> {
  RepoController get ctrl => widget.ctrl;

  final _pattern = TextEditingController();
  final _url = TextEditingController();
  late Future<LfsServerConfig> _server = _loadServer();
  LfsUrlSource? _source;
  LfsServerTest? _test;
  var _testing = false;

  Future<LfsServerConfig> _loadServer() async {
    final config = await ctrl.repo.lfsServerConfig();
    if (mounted) {
      setState(() {
        _source = config.source;
        _url.text =
            config.localUrl ?? config.sharedUrl ?? config.effective ?? '';
      });
    }
    return config;
  }

  @override
  void dispose() {
    _pattern.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _track() async {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) return;
    if (await ctrl.lfsTrack([pattern])) _pattern.clear();
  }

  Future<void> _saveServer() async {
    final source = _source ?? LfsUrlSource.automatic;
    final url = _url.text.trim();
    if (source != LfsUrlSource.automatic &&
        !url.startsWith('http') &&
        !url.startsWith('ssh')) {
      await showConfirmDialog(context,
          title: 'LFS Server',
          message: 'Enter a URL such as https://lfs.example.com/team/app');
      return;
    }
    await ctrl.setLfsServer(source, url);
    setState(() {
      _test = null;
      _server = _loadServer();
    });
  }

  Future<void> _runTest(String endpoint) async {
    setState(() {
      _testing = true;
      _test = null;
    });
    final result =
        await testLfsServer(endpoint, credential: ctrl.lfsCredential?.git);
    if (mounted) {
      setState(() {
        _testing = false;
        _test = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final lfs = ctrl.lfs;
        return IdeDialog(
          title: 'Git LFS · ${ctrl.name}',
          width: 640,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _status(lfs),
                if (lfs.installed) ...[
                  _divider(),
                  _tracking(lfs),
                  _divider(),
                  _serverSection(),
                  _divider(),
                  _credentialsSection(),
                ],
              ],
            ),
          ),
          actions: [
            IdeButton(
                label: 'Close',
                primary: true,
                onPressed: () => Navigator.pop(context)),
          ],
        );
      },
    );
  }

  Widget _divider() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(vertical: 14),
        color: IdeColors.of(context).border,
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  Widget _status(LfsState lfs) {
    final c = IdeColors.of(context);
    if (!lfs.installed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.error_outline, size: 18, color: c.error),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('git-lfs is not installed on this computer.')),
        ]),
        const SizedBox(height: 8),
        Text(
          'Git for Windows includes it. Elsewhere, install it from git-lfs.com or your package '
          'manager (for example "brew install git-lfs" or "apt install git-lfs"), then reopen EasyGit.',
          style: TextStyle(color: c.textSecondary),
        ),
        const SizedBox(height: 8),
        IdeButton(
          label: 'Open git-lfs.com',
          onPressed: () => launchUrl(Uri.parse('https://git-lfs.com'),
              mode: LaunchMode.externalApplication),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(lfs.version!,
          style: monoStyle(context, size: 12, color: c.textSecondary)),
      const SizedBox(height: 8),
      if (!lfs.usesLfs)
        const Text(
            'This repository does not use LFS yet. Track a file pattern below to start.')
      else if (!lfs.hooksInstalled)
        Row(children: [
          Icon(Icons.warning_amber, size: 18, color: c.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
                'LFS hooks are not installed here, so pushes would not upload LFS files.'),
          ),
          IdeButton(
              label: 'Set Up', primary: true, onPressed: ctrl.lfsInstallHooks),
        ])
      else
        Row(children: [
          Icon(Icons.check_circle_outline, size: 18, color: c.success),
          const SizedBox(width: 8),
          const Text('Git LFS is set up for this repository.'),
        ]),
    ]);
  }

  Widget _tracking(LfsState lfs) {
    final c = IdeColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Tracked patterns'),
      if (lfs.patterns.isEmpty)
        Text('None yet.', style: TextStyle(color: c.textSecondary))
      else
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in lfs.patterns)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.hover,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(p, style: monoStyle(context, size: 12)),
            ),
        ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: IdeTextField(
            controller: _pattern,
            hint: 'Pattern to store with LFS, e.g. *.psd or assets/**',
            onSubmitted: (_) => _track(),
          ),
        ),
        const SizedBox(width: 6),
        IdeButton(label: 'Track', onPressed: _track),
      ]),
      const SizedBox(height: 4),
      Text(
          'Tracking edits .gitattributes; commit it so everyone stores these files with LFS.',
          style: TextStyle(fontSize: 12, color: c.textSecondary)),
    ]);
  }

  Widget _serverSection() {
    final c = IdeColors.of(context);
    return FutureBuilder<LfsServerConfig>(
      future: _server,
      builder: (context, snapshot) {
        final config = snapshot.data;
        final endpoint = ctrl.lfs.endpoint ?? config?.effective;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _heading('Server'),
          Row(children: [
            Expanded(
              child: SelectableText(endpoint ?? '(no remote yet)',
                  style: monoStyle(context, size: 12.5)),
            ),
            if (endpoint != null)
              IdeButton(
                label: _testing ? 'Testing...' : 'Test',
                onPressed: _testing ? null : () => _runTest(endpoint),
              ),
          ]),
          if (config != null)
            Text('From: ${config.source.label}',
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
          if (_test != null) ...[
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                  _test!.status == LfsServerStatus.ok
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 16,
                  color: _test!.status == LfsServerStatus.ok
                      ? c.success
                      : c.error),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_test!.summary),
                      SelectableText(_test!.detail,
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary)),
                    ]),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Text(
              'Use a different LFS server (self-hosted, or separate from the Git host):',
              style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 4),
          for (final s in LfsUrlSource.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _source = s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(
                      _source == s
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: _source == s ? c.accent : c.buttonBorder),
                  const SizedBox(width: 8),
                  Flexible(child: Text(s.label)),
                ]),
              ),
            ),
          if (_source != null && _source != LfsUrlSource.automatic) ...[
            const SizedBox(height: 6),
            IdeTextField(
                controller: _url, hint: 'https://lfs.example.com/team/app'),
          ],
          const SizedBox(height: 8),
          Row(children: [
            IdeButton(label: 'Apply', onPressed: _saveServer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'A self-hosted server can use an account (Accounts > Add > Other server), or '
                'the LFS credentials below.',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
          ]),
        ]);
      },
    );
  }

  // ----------------------------------------------------------- credentials

  Widget _credentialsSection() {
    final c = IdeColors.of(context);
    final credential = ctrl.lfsCredential;
    final endpoint = ctrl.lfs.endpoint;
    final matches = credential?.matches(endpoint) ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Credentials'),
      Text(
        'Git-lfs authenticates with your EasyGit accounts. When the LFS server is separate '
        'from the Git remote, or needs a token of its own, save credentials here: git-lfs uses '
        'them for this repository only, and they stay in the system credential store.',
        style: TextStyle(color: c.textSecondary),
      ),
      const SizedBox(height: 10),
      if (credential == null)
        Row(children: [
          Expanded(
            child: Text('No LFS credentials saved; the accounts are used.',
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ),
          IdeButton(
              label: 'Set Credentials...',
              primary: true,
              onPressed:
                  ctrl.busy == null ? () => _setCredentials(endpoint) : null),
        ])
      else
        Row(children: [
          Icon(Icons.key_outlined, size: 18, color: c.icon),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${credential.username} at ${credential.server}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 12.5)),
              Text(
                matches
                    ? 'Used by git-lfs for this repository.'
                    : 'Saved for another server; the LFS server of this repository is '
                        '${LfsCredential.serverOf(endpoint) ?? 'not known'}.',
                style: TextStyle(
                    fontSize: 12, color: matches ? c.textSecondary : c.warning),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          IdeButton(label: 'Change...', onPressed: () => _setCredentials(endpoint)),
          const SizedBox(width: 8),
          IdeButton(label: 'Remove', onPressed: _removeCredentials),
        ]),
    ]);
  }

  Future<void> _setCredentials(String? endpoint) async {
    final result = await showDialog<({String server, String username, String token})>(
      context: context,
      builder: (context) => _LfsCredentialDialog(
        server: LfsCredential.serverOf(endpoint) ?? '',
        username: ctrl.lfsCredential?.username ?? '',
      ),
    );
    if (result == null) return;
    final ok = await ctrl.setLfsCredentials(
        server: result.server, username: result.username, token: result.token);
    if (ok && mounted) setState(() => _test = null);
  }

  Future<void> _removeCredentials() async {
    final ok = await showConfirmDialog(context,
        title: 'Remove LFS Credentials',
        message: 'git-lfs falls back to your EasyGit accounts for the LFS server.\n\n'
            'The saved token is deleted from this computer.',
        okLabel: 'Remove');
    if (!ok) return;
    await ctrl.clearLfsCredentials();
    if (mounted) setState(() => _test = null);
  }
}

/// Asks for the credentials git-lfs uses for one LFS server.
class _LfsCredentialDialog extends StatefulWidget {
  const _LfsCredentialDialog({required this.server, required this.username});

  final String server;
  final String username;

  @override
  State<_LfsCredentialDialog> createState() => _LfsCredentialDialogState();
}

class _LfsCredentialDialogState extends State<_LfsCredentialDialog> {
  late final _server = TextEditingController(text: widget.server);
  late final _username = TextEditingController(text: widget.username);
  final _token = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _token.dispose();
    super.dispose();
  }

  void _submit() {
    final server = LfsCredential.serverOf(_server.text);
    if (server == null) {
      setState(() => _error = 'Enter the server as https://host or https://host:port.');
      return;
    }
    if (_username.text.trim().isEmpty) {
      setState(() => _error = 'Enter a username.');
      return;
    }
    if (_token.text.trim().isEmpty) {
      setState(() => _error = 'Enter a password or token.');
      return;
    }
    Navigator.pop(context,
        (server: server, username: _username.text.trim(), token: _token.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return IdeDialog(
      title: 'LFS Credentials',
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'git-lfs uses these for the LFS server of this repository only. They stay in '
            "this computer's credential store; nothing is written to the repository.",
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          const Text('Server (scheme and host):'),
          const SizedBox(height: 6),
          IdeTextField(controller: _server, hint: 'https://lfs.example.com'),
          const SizedBox(height: 10),
          const Text('Username:'),
          const SizedBox(height: 6),
          IdeTextField(
              controller: _username,
              autofocus: true,
              onSubmitted: (_) => _submit()),
          const SizedBox(height: 10),
          const Text('Password or token:'),
          const SizedBox(height: 6),
          IdeSecretField(controller: _token, onSubmitted: _submit),
          const SizedBox(height: 6),
          Text(
            'For a standalone LFS server a personal access token usually works as the '
            'password.',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: c.error)),
          ],
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Save', primary: true, onPressed: _submit),
      ],
    );
  }
}
