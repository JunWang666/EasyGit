import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../git/git_runner.dart';

enum ProxyMode {
  /// Do nothing: git uses its own configuration and environment.
  gitConfig('Use Git\'s configuration'),

  /// Follow the operating system's proxy settings.
  system('Use system proxy'),

  /// A proxy entered in EasyGit.
  manual('Manual'),

  /// Force direct connections, even if gitconfig sets a proxy.
  none('No proxy');

  const ProxyMode(this.label);

  final String label;
}

/// A proxy for one server, applied on top of the general [ProxyMode].
class ProxyRule {
  const ProxyRule(this.host, this.proxy);

  /// `github.com`, or `*.example.com` for its subdomains.
  final String host;

  /// Proxy URL, or empty to connect directly.
  final String proxy;

  bool get isDirect => proxy.trim().isEmpty;
  bool get isValid => RegExp(r'^(\*\.)?[A-Za-z0-9.-]+(:\d+)?$').hasMatch(host.trim());

  bool matches(String uriHost) {
    final h = uriHost.toLowerCase();
    final p = host.trim().toLowerCase().split(':').first;
    if (p.startsWith('*.')) return h.endsWith(p.substring(1));
    return h == p;
  }

  Map<String, String> toJson() => {'host': host, 'proxy': proxy};

  static ProxyRule fromJson(Map<String, dynamic> j) =>
      ProxyRule(j['host'] as String? ?? '', j['proxy'] as String? ?? '');
}

/// A proxy that is actually in effect.
class ResolvedProxy {
  const ResolvedProxy(this.url, {this.bypass = const []});

  /// `http://host:port` or `socks5h://host:port`, without credentials.
  final String url;
  final List<String> bypass;

  Uri get uri => Uri.parse(url);
  bool get isSocks => uri.scheme.startsWith('socks');
  String get hostPort => '${uri.host}:${uri.port}';
}

/// Result of reading the OS proxy settings.
class SystemProxy {
  const SystemProxy({this.proxy, this.pacUrl, this.source = ''});

  final ResolvedProxy? proxy;

  /// Set when the system uses an auto-config (PAC) script, which git cannot use.
  final String? pacUrl;
  final String source;
}

/// Proxy settings for git, git-lfs and EasyGit's own HTTP requests.
class NetworkSettings extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _passwordKey = 'easygit.proxy.password';

  /// The settings in effect, for code without access to the instance.
  static NetworkSettings? current;

  ProxyMode mode = ProxyMode.gitConfig;
  String manualUrl = 'http://127.0.0.1:7890';
  String username = '';
  String _password = '';

  /// Extra hosts that bypass the proxy (NO_PROXY), comma separated.
  String bypass = 'localhost,127.0.0.1';

  /// Hosts of self-hosted servers are added to the bypass list.
  bool bypassSelfHosted = false;

  /// Hosts of self-hosted accounts, provided by the accounts store.
  List<String> selfHostedHosts = const [];

  /// Per-server proxies. They apply in every mode and win over it.
  List<ProxyRule> rules = const [];

  SystemProxy? system;

  bool get hasPassword => _password.isNotEmpty;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      mode = ProxyMode.values.where((m) => m.name == p.getString('proxy.mode')).firstOrNull ??
          ProxyMode.gitConfig;
      manualUrl = p.getString('proxy.url') ?? manualUrl;
      username = p.getString('proxy.user') ?? '';
      bypass = p.getString('proxy.bypass') ?? bypass;
      bypassSelfHosted = p.getBool('proxy.bypassSelfHosted') ?? false;
      final rawRules = p.getString('proxy.rules');
      if (rawRules != null) {
        rules = [
          for (final r in jsonDecode(rawRules) as List)
            ProxyRule.fromJson(r as Map<String, dynamic>)
        ];
      }
      _password = await _storage.read(key: _passwordKey) ?? '';
    } catch (e) {
      debugPrint('Cannot load network settings: $e');
    }
    current = this;
    await refreshSystem();
  }

  Future<void> save({
    required ProxyMode mode,
    required String manualUrl,
    required String username,
    String? password,
    required String bypass,
    required bool bypassSelfHosted,
    List<ProxyRule>? rules,
  }) async {
    this.mode = mode;
    if (rules != null) {
      this.rules = [
        for (final r in rules)
          if (r.host.trim().isNotEmpty)
            ProxyRule(r.host.trim(), r.isDirect ? '' : normalizeProxyUrl(r.proxy)),
      ];
    }
    this.manualUrl = manualUrl.trim();
    this.username = username.trim();
    if (password != null) _password = password;
    this.bypass = bypass;
    this.bypassSelfHosted = bypassSelfHosted;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('proxy.mode', mode.name);
      await p.setString('proxy.url', this.manualUrl);
      await p.setString('proxy.user', this.username);
      await p.setString('proxy.bypass', bypass);
      await p.setBool('proxy.bypassSelfHosted', bypassSelfHosted);
      await p.setString('proxy.rules', jsonEncode([for (final r in this.rules) r.toJson()]));
      if (password != null) {
        password.isEmpty
            ? await _storage.delete(key: _passwordKey)
            : await _storage.write(key: _passwordKey, value: password);
      }
    } catch (e) {
      debugPrint('Cannot save network settings: $e');
    }
    _publish();
  }

  Future<void> refreshSystem() async {
    system = await detectSystemProxy();
    _publish();
  }

  void setSelfHostedHosts(List<String> hosts) {
    selfHostedHosts = hosts;
    _publish();
  }

  /// The proxy EasyGit applies, or null for none / git's own configuration.
  ResolvedProxy? get effective => switch (mode) {
        ProxyMode.manual => manualUrl.isEmpty
            ? null
            : ResolvedProxy(normalizeProxyUrl(manualUrl), bypass: bypassList),
        ProxyMode.system => system?.proxy == null
            ? null
            : ResolvedProxy(system!.proxy!.url, bypass: [...bypassList, ...system!.proxy!.bypass]),
        _ => null,
      };

  List<String> get bypassList => {
        ...bypass.split(RegExp(r'[,;\s]+')).where((s) => s.isNotEmpty),
        if (bypassSelfHosted) ...selfHostedHosts,
      }.toList();

  /// Proxy URL with credentials, for git only.
  String? get _gitProxyUrl {
    final p = effective;
    if (p == null) return null;
    if (mode != ProxyMode.manual || username.isEmpty) return p.url;
    final u = p.uri;
    return u
        .replace(userInfo: '${Uri.encodeComponent(username)}:${Uri.encodeComponent(_password)}')
        .toString();
  }

  void _publish() {
    GitRunner.networkEnv = gitEnvironment();
    notifyListeners();
  }

  /// Environment for git processes. Config entries use GIT_CONFIG_COUNT,
  /// which git and git-lfs both read, so nothing shows up in process lists.
  Map<String, String> gitEnvironment() {
    final config = <(String, String)>[];
    final env = <String, String>{};
    switch (mode) {
      case ProxyMode.gitConfig:
        break;
      case ProxyMode.none:
        config.add(('http.proxy', ''));
        for (final k in ['HTTPS_PROXY', 'HTTP_PROXY', 'ALL_PROXY']) {
          env[k] = '';
          env[k.toLowerCase()] = '';
        }
      case ProxyMode.system:
      case ProxyMode.manual:
        final url = _gitProxyUrl;
        if (url == null) break;
        config.add(('http.proxy', url));
        // Hosts with their own rule must not be bypassed by NO_PROXY.
        final noProxy = bypassList
            .where((b) => !rules.any((r) => !r.isDirect && r.matches(b.replaceFirst('*.', ''))))
            .join(',');
        if (noProxy.isNotEmpty) env.addAll({'NO_PROXY': noProxy, 'no_proxy': noProxy});
    }
    // git matches http.<url>.proxy by URL, more specific than http.proxy.
    // An empty value means a direct connection.
    for (final r in rules) {
      if (!r.isValid) continue;
      for (final scheme in ['https', 'http']) {
        config.add(('http.$scheme://${r.host.trim()}.proxy', r.proxy));
      }
    }
    if (config.isEmpty) return env;
    return {
      ...env,
      'GIT_CONFIG_COUNT': '${config.length}',
      for (var i = 0; i < config.length; i++) ...{
        'GIT_CONFIG_KEY_$i': config[i].$1,
        'GIT_CONFIG_VALUE_$i': config[i].$2,
      },
    };
  }

  /// The rule for [host], if any.
  ProxyRule? ruleFor(String host) => rules.where((r) => r.isValid && r.matches(host)).firstOrNull;

  /// Proxy for EasyGit's own requests (hosting APIs, LFS server test).
  /// Dart's HttpClient only speaks HTTP proxies, so SOCKS falls back to direct.
  static String findProxy(Uri uri) {
    final s = current;
    if (s == null) return 'DIRECT';
    if (s.ruleFor(uri.host) case final rule?) {
      if (rule.isDirect) return 'DIRECT';
      final u = Uri.tryParse(normalizeProxyUrl(rule.proxy));
      if (u == null || u.scheme.startsWith('socks')) return 'DIRECT';
      return 'PROXY ${u.host}:${u.hasPort ? u.port : 80}';
    }
    if (s.mode == ProxyMode.none) return 'DIRECT';
    final p = s.effective;
    if (p == null) {
      if (s.mode == ProxyMode.gitConfig) return HttpClient.findProxyFromEnvironment(uri);
      return 'DIRECT';
    }
    if (p.isSocks || _bypassed(uri.host, p.bypass)) return 'DIRECT';
    return 'PROXY ${p.hostPort}';
  }

  static bool _bypassed(String host, List<String> bypass) {
    final h = host.toLowerCase();
    for (var b in bypass) {
      b = b.toLowerCase().trim();
      if (b.isEmpty) continue;
      if (b == '*' || b == '<local>' && !h.contains('.')) return true;
      if (b.startsWith('*.')) b = b.substring(1);
      if (h == b || (b.startsWith('.') ? h.endsWith(b) : h.endsWith('.$b'))) return true;
    }
    return false;
  }

  /// An HttpClient that follows these settings.
  static HttpClient httpClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = findProxy;
    final s = current;
    if (s != null && s.mode == ProxyMode.manual && s.username.isNotEmpty) {
      final p = s.effective;
      if (p != null && !p.isSocks) {
        client.addProxyCredentials(
            p.uri.host, p.uri.port, '', HttpClientBasicCredentials(s.username, s._password));
      }
    }
    return client;
  }
}

/// Adds a scheme when missing: `127.0.0.1:7890` -> `http://127.0.0.1:7890`.
String normalizeProxyUrl(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  return s.contains('://') ? s : 'http://$s';
}

// ---------------------------------------------------------------- system proxy

Future<SystemProxy> detectSystemProxy() async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run(
          'reg', ['query', r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings']);
      return parseWindowsProxy(r.stdout as String);
    }
    if (Platform.isMacOS) {
      final r = await Process.run('scutil', ['--proxy']);
      return parseMacProxy(r.stdout as String);
    }
  } catch (e) {
    debugPrint('Cannot read system proxy: $e');
  }
  final env = Platform.environment;
  final url = env['https_proxy'] ?? env['HTTPS_PROXY'] ?? env['all_proxy'] ?? env['ALL_PROXY'];
  final noProxy = env['no_proxy'] ?? env['NO_PROXY'] ?? '';
  return SystemProxy(
    proxy: url == null || url.isEmpty
        ? null
        : ResolvedProxy(normalizeProxyUrl(url),
            bypass: noProxy.split(',').where((s) => s.isNotEmpty).toList()),
    source: 'environment variables',
  );
}

/// Parses `reg query ...\Internet Settings` output.
SystemProxy parseWindowsProxy(String out) {
  String? value(String name) =>
      RegExp('^\\s*$name\\s+REG_\\w+\\s+(.*)\$', multiLine: true).firstMatch(out)?[1]?.trim();
  final pac = value('AutoConfigURL');
  final enabled = value('ProxyEnable');
  final server = value('ProxyServer');
  if (enabled == null || !enabled.endsWith('1') || server == null || server.isEmpty) {
    return SystemProxy(pacUrl: pac, source: 'Windows settings');
  }
  String? url;
  if (server.contains('=')) {
    final parts = {
      for (final p in server.split(';'))
        if (p.contains('='))
          p.substring(0, p.indexOf('=')).toLowerCase(): p.substring(p.indexOf('=') + 1),
    };
    if (parts['https'] != null) {
      url = 'http://${parts['https']}';
    } else if (parts['http'] != null) {
      url = 'http://${parts['http']}';
    } else if (parts['socks'] != null) {
      url = 'socks5h://${parts['socks']}';
    }
  } else {
    url = normalizeProxyUrl(server);
  }
  final bypass = (value('ProxyOverride') ?? '').split(';').where((s) => s.isNotEmpty).toList();
  return SystemProxy(
    proxy: url == null ? null : ResolvedProxy(url, bypass: bypass),
    pacUrl: pac,
    source: 'Windows settings',
  );
}

/// Parses `scutil --proxy` output.
SystemProxy parseMacProxy(String out) {
  String? value(String key) =>
      RegExp('^\\s*$key\\s*:\\s*(.+)\$', multiLine: true).firstMatch(out)?[1]?.trim();
  String? url;
  if (value('HTTPSEnable') == '1' && value('HTTPSProxy') != null) {
    url = 'http://${value('HTTPSProxy')}:${value('HTTPSPort') ?? '443'}';
  } else if (value('HTTPEnable') == '1' && value('HTTPProxy') != null) {
    url = 'http://${value('HTTPProxy')}:${value('HTTPPort') ?? '80'}';
  } else if (value('SOCKSEnable') == '1' && value('SOCKSProxy') != null) {
    url = 'socks5h://${value('SOCKSProxy')}:${value('SOCKSPort') ?? '1080'}';
  }
  final exceptions = RegExp(r'^\s*\d+\s*:\s*(\S+)$', multiLine: true)
      .allMatches(out.split('ExceptionsList').length > 1 ? out.split('ExceptionsList')[1] : '')
      .map((m) => m[1]!)
      .toList();
  final pac = value('ProxyAutoConfigEnable') == '1' ? value('ProxyAutoConfigURLString') : null;
  return SystemProxy(
    proxy: url == null ? null : ResolvedProxy(url, bypass: exceptions),
    pacUrl: pac,
    source: 'macOS settings',
  );
}

// ---------------------------------------------------------------- error hints

/// A short explanation for network failures in git's stderr, if recognised.
String? networkHint(String message) {
  final m = message.toLowerCase();
  if (m.contains('over proxy') ||
      m.contains('proxyconnect') ||
      m.contains('proxy connect') ||
      m.contains('could not resolve proxy')) {
    return 'The proxy could not be reached. Check that it is running, or change it in Network settings.';
  }
  if (m.contains('ssl certificate problem') ||
      m.contains('certificate signed by unknown authority') ||
      m.contains('x509:')) {
    return 'The server\'s certificate is not trusted. A self-hosted server may need its CA certificate configured.';
  }
  if (m.contains('could not resolve host') || m.contains('no such host')) {
    return 'The server name could not be resolved. If you need a proxy to reach it, set one in Network settings.';
  }
  if (m.contains('timed out') ||
      m.contains('connection reset') ||
      m.contains('failed to connect') ||
      m.contains('connection refused')) {
    return 'The connection failed. If this network needs a proxy, set one in Network settings.';
  }
  if (m.contains('authentication failed') ||
      RegExp(r'(error: |\[|http |status )(401|403)\b').hasMatch(m) ||
      m.contains('could not read username')) {
    return 'The server rejected the credentials. Sign in under Accounts (self-hosted servers: "Other server").';
  }
  return null;
}
