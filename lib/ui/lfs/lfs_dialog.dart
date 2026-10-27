import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../git/lfs.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// Git LFS overview for a repository: setup, files, tracking and server.
Future<void> showLfsDialog(BuildContext context, RepoController ctrl) =>
    showDialog<void>(context: context, builder: (context) => _LfsDialog(ctrl: ctrl));

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
        _url.text = config.localUrl ?? config.sharedUrl ?? config.effective ?? '';
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
    if (source != LfsUrlSource.automatic && !url.startsWith('http') && !url.startsWith('ssh')) {
      await showConfirmDialog(context,
          title: 'LFS Server', message: 'Enter a URL such as https://lfs.example.com/team/app');
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
    final result = await testLfsServer(endpoint);
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
                  _files(lfs),
                  _divider(),
                  _tracking(lfs),
                  _divider(),
                  _serverSection(),
                ],
              ],
            ),
          ),
          actions: [
            IdeButton(label: 'Close', primary: true, onPressed: () => Navigator.pop(context)),
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
          const Expanded(child: Text('git-lfs is not installed on this computer.')),
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
          onPressed: () =>
              launchUrl(Uri.parse('https://git-lfs.com'), mode: LaunchMode.externalApplication),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(lfs.version!, style: monoStyle(context, size: 12, color: c.textSecondary)),
      const SizedBox(height: 8),
      if (!lfs.usesLfs)
        const Text('This repository does not use LFS yet. Track a file pattern below to start.')
      else if (!lfs.hooksInstalled)
        Row(children: [
          Icon(Icons.warning_amber, size: 18, color: c.warning),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('LFS hooks are not installed here, so pushes would not upload LFS files.'),
          ),
          IdeButton(label: 'Set Up', primary: true, onPressed: ctrl.lfsInstallHooks),
        ])
      else
        Row(children: [
          Icon(Icons.check_circle_outline, size: 18, color: c.success),
          const SizedBox(width: 8),
          const Text('Git LFS is set up for this repository.'),
        ]),
    ]);
  }

  Widget _files(LfsState lfs) {
    final c = IdeColors.of(context);
    final total = lfs.files.values.fold<int>(0, (s, f) => s + f.size);
    final missing = lfs.missing;
    final missingBytes = missing.fold<int>(0, (s, f) => s + f.size);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Files'),
      Text('${lfs.files.length} file${lfs.files.length == 1 ? '' : 's'} in LFS · ${formatBytes(total)}'),
      if (missing.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.cloud_download_outlined, size: 17, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${missing.length} not downloaded (${formatBytes(missingBytes)}). '
                'Their working-tree copies are small pointer files.'),
          ),
          IdeButton(
            label: 'Download All',
            primary: true,
            onPressed: ctrl.busy == null ? () => ctrl.lfsDownload() : null,
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          decoration: BoxDecoration(
            color: c.editorBg,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(5),
          ),
          child: ListView(shrinkWrap: true, children: [
            for (final f in missing.take(200))
              Container(
                height: 30,
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(children: [
                  Expanded(
                    child: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(formatBytes(f.size), style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  IdeIconButton(
                    icon: Icons.download,
                    tooltip: 'Download',
                    size: 24,
                    iconSize: 14,
                    onPressed: ctrl.busy == null ? () => ctrl.lfsDownload([f.path]) : null,
                  ),
                ]),
              ),
          ]),
        ),
      ],
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
      Text('Tracking edits .gitattributes; commit it so everyone stores these files with LFS.',
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
              Icon(_test!.status == LfsServerStatus.ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 16, color: _test!.status == LfsServerStatus.ok ? c.success : c.error),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_test!.summary),
                  SelectableText(_test!.detail,
                      style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ]),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Text('Use a different LFS server (self-hosted, or separate from the Git host):',
              style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 4),
          for (final s in LfsUrlSource.values)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _source = s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(_source == s ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      size: 16, color: _source == s ? c.accent : c.buttonBorder),
                  const SizedBox(width: 8),
                  Text(s.label),
                ]),
              ),
            ),
          if (_source != null && _source != LfsUrlSource.automatic) ...[
            const SizedBox(height: 6),
            IdeTextField(controller: _url, hint: 'https://lfs.example.com/team/app'),
          ],
          const SizedBox(height: 8),
          Row(children: [
            IdeButton(label: 'Apply', onPressed: _saveServer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Credentials for a self-hosted server: Accounts > Add > Other server.',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
          ]),
        ]);
      },
    );
  }
}
