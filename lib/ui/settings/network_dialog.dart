import 'dart:io';

import 'package:flutter/material.dart';

import '../../git/git_runner.dart';
import '../../git/models.dart';
import '../../net/network.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';

class _RuleFields {
  _RuleFields(String host, String proxy)
      : host = TextEditingController(text: host),
        proxy = TextEditingController(text: proxy);

  final TextEditingController host;
  final TextEditingController proxy;

  void dispose() {
    host.dispose();
    proxy.dispose();
  }
}

class _TestResult {
  const _TestResult(this.label, this.ok, this.detail);

  final String label;
  final bool ok;
  final String detail;
}

/// Settings > Network & Proxy: how git, git-lfs and EasyGit reach servers.
class NetworkSettingsPanel extends StatefulWidget {
  const NetworkSettingsPanel({super.key, required this.repos});

  final ReposState repos;

  @override
  State<NetworkSettingsPanel> createState() => _NetworkSettingsPanelState();
}

class _NetworkSettingsPanelState extends State<NetworkSettingsPanel> {
  NetworkSettings get net => widget.repos.network;

  late var _mode = net.mode;
  late final _url = TextEditingController(text: net.manualUrl);
  late final _user = TextEditingController(text: net.username);
  final _password = TextEditingController();
  late final _bypass = TextEditingController(text: net.bypass);
  late var _bypassSelfHosted = net.bypassSelfHosted;
  late final _rules = [for (final r in net.rules) _RuleFields(r.host, r.proxy)];
  var _testing = false;
  var _saved = false;
  List<_TestResult>? _results;

  @override
  void initState() {
    super.initState();
    net.refreshSystem().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    _bypass.dispose();
    for (final r in _rules) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _apply() => net.save(
        rules: [for (final r in _rules) ProxyRule(r.host.text, r.proxy.text)],
        mode: _mode,
        manualUrl: normalizeProxyUrl(_url.text),
        username: _user.text,
        password: _password.text.isEmpty ? null : _password.text,
        bypass: _bypass.text,
        bypassSelfHosted: _bypassSelfHosted,
      );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _results = null;
    });
    await _apply();
    final results = <_TestResult>[];

    // Git: list refs of the selected repository's remote (or a public one).
    final ctrl = widget.repos.current;
    final remote = ctrl?.primaryRemote;
    final remoteUrl = remote == null ? null : ctrl!.remoteUrls[remote];
    final target = remoteUrl ?? 'https://github.com/git/git.git';
    final watch = Stopwatch()..start();
    try {
      await GitRunner(ctrl?.repo.root ?? Directory.systemTemp.path)
          .run(['ls-remote', '--heads', target], timeout: const Duration(seconds: 20));
      results.add(_TestResult('Git ($target)', true, '${watch.elapsedMilliseconds} ms'));
    } on GitException catch (e) {
      results.add(_TestResult('Git ($target)', false, e.message.split('\n').last));
    }

    // EasyGit's own HTTPS requests (account APIs, LFS server test).
    watch.reset();
    final client = NetworkSettings.httpClient();
    try {
      final request = await client.getUrl(Uri.parse('https://api.github.com/zen'));
      request.headers.set(HttpHeaders.userAgentHeader, 'EasyGit');
      final response = await request.close().timeout(const Duration(seconds: 15));
      await response.drain<void>();
      results.add(_TestResult('EasyGit HTTPS (api.github.com)', response.statusCode < 500,
          'HTTP ${response.statusCode}, ${watch.elapsedMilliseconds} ms'));
    } catch (e) {
      results.add(_TestResult('EasyGit HTTPS (api.github.com)', false, '$e'));
    } finally {
      client.close(force: true);
    }

    if (mounted) {
      setState(() {
        _testing = false;
        _results = results;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final system = net.system;
    final socks = _mode == ProxyMode.manual && normalizeProxyUrl(_url.text).startsWith('socks') ||
        _mode == ProxyMode.system && (system?.proxy?.isSocks ?? false);

    String describe(ProxyMode m) => switch (m) {
          ProxyMode.gitConfig => 'EasyGit changes nothing. Git uses http.proxy from your gitconfig '
              'and the HTTPS_PROXY / NO_PROXY environment variables.',
          ProxyMode.system => system?.proxy != null
              ? 'Detected ${system!.proxy!.url} (${system.source}).'
              : (system?.pacUrl != null
                  ? 'The system uses an auto-config script (${system!.pacUrl}), which Git cannot use. '
                      'Enter the proxy manually instead.'
                  : 'No system proxy is set right now.'),
          ProxyMode.manual => 'For example http://127.0.0.1:7890 or socks5h://127.0.0.1:7891.',
          ProxyMode.none => 'Connect directly, even if your gitconfig sets a proxy.',
        };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Applies to fetch, pull, push and clone, to Git LFS transfers, and to EasyGit\'s '
          'requests to GitHub, GitLab and Gitea. Your global gitconfig is never changed.',
          style: TextStyle(color: c.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final m in ProxyMode.values)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _mode = m),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_mode == m ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 16, color: _mode == m ? c.accent : c.buttonBorder),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.label),
                    Text(describe(m), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
          ),
        if (_mode == ProxyMode.manual) ...[
          const SizedBox(height: 8),
          _label('Proxy address'),
          IdeTextField(
            controller: _url,
            hint: 'http://127.0.0.1:7890',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('Username (optional)'),
                IdeTextField(controller: _user),
              ]),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(net.hasPassword ? 'Password (saved; type to change)' : 'Password'),
                _PasswordField(controller: _password),
              ]),
            ),
          ]),
        ],
        if (_mode == ProxyMode.manual || _mode == ProxyMode.system) ...[
          const SizedBox(height: 10),
          _label('Connect directly to (NO_PROXY)'),
          IdeTextField(controller: _bypass, hint: 'localhost,127.0.0.1,.corp.example.com'),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _bypassSelfHosted = !_bypassSelfHosted),
            child: Row(children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _bypassSelfHosted,
                  activeColor: c.accent,
                  onChanged: (v) => setState(() => _bypassSelfHosted = v ?? false),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Connect directly to my self-hosted servers'
                  '${net.selfHostedHosts.isEmpty ? '' : ' (${net.selfHostedHosts.join(', ')})'}',
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        const Text('Per-server rules', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Use a different proxy, or none, for some servers. Rules apply whatever is chosen '
          'above. Use *.example.com for all subdomains.',
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
        const SizedBox(height: 8),
        for (final (i, r) in _rules.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Expanded(
                flex: 2,
                child: IdeTextField(controller: r.host, hint: 'github.com'),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: IdeTextField(
                    controller: r.proxy, hint: 'http://127.0.0.1:7890, or empty for direct'),
              ),
              IdeIconButton(
                icon: Icons.close,
                tooltip: 'Remove Rule',
                onPressed: () => setState(() => _rules.removeAt(i).dispose()),
              ),
            ]),
          ),
        HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: () => setState(() => _rules.add(_RuleFields('', ''))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add, size: 16, color: c.accent),
              const SizedBox(width: 4),
              Text('Add Rule',
                  style: TextStyle(
                      color: c.accent, decoration: hovered ? TextDecoration.underline : null)),
            ]),
          ),
        ),
        if (socks) ...[
          const SizedBox(height: 10),
          Text(
            'Git and Git LFS use the SOCKS proxy. EasyGit\'s own requests (account repository '
            'lists, LFS server test) cannot use SOCKS and connect directly. Use an HTTP or '
            '"mixed" port to cover them too.',
            style: TextStyle(fontSize: 12, color: c.warning),
          ),
        ],
        if (_results != null || _testing) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: c.editorBg,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: _testing
                ? const Row(children: [
                    SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('Testing connections...'),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final r in _results!)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(r.ok ? Icons.check_circle_outline : Icons.error_outline,
                              size: 16, color: r.ok ? c.success : c.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.label),
                              SelectableText(r.detail,
                                  style: TextStyle(fontSize: 12, color: c.textSecondary)),
                              if (!r.ok && networkHint(r.detail) != null)
                                Text(networkHint(r.detail)!, style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
          ),
        ],
        const SizedBox(height: 18),
        Row(children: [
          IdeButton(
            label: 'Save',
            primary: true,
            onPressed: () async {
              await _apply();
              if (!mounted) return;
              setState(() => _saved = true);
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _saved = false);
              });
            },
          ),
          const SizedBox(width: 8),
          IdeButton(label: 'Save & Test', onPressed: _testing ? null : _test),
          if (_saved) ...[
            const SizedBox(width: 10),
            Icon(Icons.check, size: 16, color: c.success),
            const SizedBox(width: 4),
            Text('Saved', style: TextStyle(color: c.success)),
          ],
        ]),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(text, style: const TextStyle(fontSize: 12.5)),
      );
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller});

  final TextEditingController controller;

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
