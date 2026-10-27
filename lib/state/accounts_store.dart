import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../git/git_runner.dart';
import '../hosting/hosting.dart';

/// Signed-in GitHub / GitLab / Gitea accounts.
///
/// Account metadata lives in preferences; tokens live in the platform's
/// secure store (Credential Manager, Keychain or libsecret).
class AccountsStore extends ChangeNotifier {
  static const _accountsKey = 'hostingAccounts';
  static const _storage = FlutterSecureStorage();

  List<HostingAccount> accounts = const [];
  final Map<String, String> _tokens = {};

  String? tokenFor(HostingAccount account) => _tokens[account.id];

  HostingAccount? accountForHost(String host) =>
      accounts.where((a) => a.host.toLowerCase() == host.toLowerCase()).firstOrNull;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountsKey);
      if (raw != null) {
        accounts = (jsonDecode(raw) as List)
            .map((e) => HostingAccount.fromJson(e as Map<String, dynamic>))
            .whereType<HostingAccount>()
            .toList();
      }
      for (final a in accounts) {
        final token = await _storage.read(key: _tokenKey(a.id));
        if (token != null) _tokens[a.id] = token;
      }
    } catch (e) {
      debugPrint('Cannot load accounts: $e');
    }
    _publishCredentials();
    notifyListeners();
  }

  /// Verifies [token] against the server and stores the account.
  Future<HostingAccount> add(HostingKind kind, String server, String token,
      {String? username}) async {
    var normalized = normalizeServer(server);
    final String login;
    if (kind.hasApi) {
      login = await HostingApi(kind, normalized, token.trim()).verify();
    } else {
      // No API to verify against. Git matches credentials by host, so keep
      // only scheme, host and port.
      final uri = Uri.tryParse(normalized);
      if (uri == null || uri.host.isEmpty) {
        throw const HostingException('Enter a server address such as https://git.example.com');
      }
      normalized = uri.origin;
      login = (username ?? '').trim();
      if (login.isEmpty) throw const HostingException('Enter a username.');
    }
    final account = HostingAccount(
      id: '${kind.name}:${Uri.parse(normalized).host}:$login',
      kind: kind,
      server: normalized,
      username: login,
    );
    await _storage.write(key: _tokenKey(account.id), value: token.trim());
    _tokens[account.id] = token.trim();
    accounts = [...accounts.where((a) => a.id != account.id), account];
    await _save();
    return account;
  }

  Future<void> remove(HostingAccount account) async {
    accounts = accounts.where((a) => a.id != account.id).toList();
    _tokens.remove(account.id);
    try {
      await _storage.delete(key: _tokenKey(account.id));
    } catch (e) {
      debugPrint('Cannot delete token: $e');
    }
    await _save();
  }

  HostingApi apiFor(HostingAccount account) =>
      HostingApi(account.kind, account.server, _tokens[account.id] ?? '');

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountsKey, jsonEncode([for (final a in accounts) a.toJson()]));
    } catch (e) {
      debugPrint('Cannot save accounts: $e');
    }
    _publishCredentials();
    notifyListeners();
  }

  /// Lets git authenticate HTTPS remotes on these servers with the tokens.
  void _publishCredentials() {
    final seen = <String>{};
    GitRunner.credentials = [
      for (final a in accounts)
        if (_tokens[a.id] != null && seen.add(a.server))
          GitCredential(
            a.server,
            a.kind == HostingKind.gitlab ? 'oauth2' : a.username,
            _tokens[a.id]!,
          ),
    ];
  }

  static String _tokenKey(String id) => 'easygit.token.$id';
}
