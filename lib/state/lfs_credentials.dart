import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../git/git_runner.dart';
import 'secure_storage.dart';

/// Credentials for one repository's LFS server.
///
/// They are kept apart from the Git account on purpose: the LFS server is often
/// a different host (a standalone LFS service), and some teams hand out a token
/// that may be used for LFS only.
class LfsCredential {
  const LfsCredential({
    required this.server,
    required this.username,
    required this.token,
  });

  /// Scheme, host and port of the LFS server, such as `https://lfs.example.com`.
  final String server;

  final String username;
  final String token;

  /// The credential git-lfs authenticates with.
  GitCredential get git => GitCredential(server, username, token);

  /// The server part of [url], or null when it is not an HTTP(S) URL.
  static String? serverOf(String? url) {
    final uri = Uri.tryParse(url?.trim() ?? '');
    if (uri == null || uri.host.isEmpty || !uri.scheme.startsWith('http')) {
      return null;
    }
    return uri.origin;
  }

  /// Whether this credential belongs to [url].
  bool matches(String? url) => serverOf(url) == server;

  Map<String, dynamic> toJson() =>
      {'server': server, 'username': username, 'token': token};

  static LfsCredential? fromJson(Map<String, dynamic> json) {
    final server = serverOf(json['server'] as String?);
    final username = (json['username'] as String? ?? '').trim();
    final token = (json['token'] as String? ?? '').trim();
    if (server == null || username.isEmpty || token.isEmpty) return null;
    return LfsCredential(server: server, username: username, token: token);
  }
}

/// Keeps LFS credentials in the system credential store, one record per
/// repository. The token never reaches `.git/config` or any file in the
/// repository.
class LfsCredentialStore {
  const LfsCredentialStore([this._storage = appSecureStorage]);

  final FlutterSecureStorage _storage;

  Future<LfsCredential?> read(String root) async {
    try {
      final raw = await _storage.read(key: keyFor(root));
      if (raw == null) return null;
      final json = jsonDecode(raw);
      return json is Map<String, dynamic> ? LfsCredential.fromJson(json) : null;
    } catch (e) {
      debugPrint('Cannot read LFS credentials: $e');
      return null;
    }
  }

  Future<bool> write(String root, LfsCredential credential) async {
    try {
      await _storage.write(
          key: keyFor(root), value: jsonEncode(credential.toJson()));
      return true;
    } catch (e) {
      debugPrint('Cannot save LFS credentials: $e');
      return false;
    }
  }

  Future<void> delete(String root) async {
    try {
      await _storage.delete(key: keyFor(root));
    } catch (e) {
      debugPrint('Cannot delete LFS credentials: $e');
    }
  }

  /// Key of the record for the repository at [root]. The path is normalized so
  /// the same folder always maps to the same entry.
  static String keyFor(String root) =>
      'easygit.lfs.${base64Url.encode(utf8.encode(_normalize(root)))}';

  static String _normalize(String path) {
    var value = path.replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return Platform.isWindows || Platform.isMacOS ? value.toLowerCase() : value;
  }
}
