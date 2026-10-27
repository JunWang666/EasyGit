import 'dart:convert';
import 'dart:io';

import '../net/network.dart';

/// Code hosting services that EasyGit can sign in to.
enum HostingKind {
  github('GitHub', 'https://github.com', 'Pull Request'),
  gitlab('GitLab', 'https://gitlab.com', 'Merge Request'),
  gitea('Gitea / Forgejo', 'https://codeberg.org', 'Pull Request'),

  /// Any self-hosted Git or LFS server: credentials only, no API.
  generic('Other server (self-hosted Git / LFS)', 'https://', 'Pull Request');

  const HostingKind(this.label, this.defaultServer, this.requestName);

  final String label;
  final String defaultServer;

  /// "Pull Request" or "Merge Request".
  final String requestName;

  /// Short name used in menus: "Open on GitHub".
  String get shortLabel => switch (this) {
        gitea => 'Gitea',
        generic => 'Server',
        _ => label,
      };

  /// Whether EasyGit can list repositories and build web links for it.
  bool get hasApi => this != generic;
}

/// A signed-in account. The token itself lives in secure storage.
class HostingAccount {
  const HostingAccount({
    required this.id,
    required this.kind,
    required this.server,
    required this.username,
  });

  final String id;
  final HostingKind kind;

  /// Web base URL without a trailing slash, e.g. `https://gitlab.example.com`.
  final String server;
  final String username;

  String get host => Uri.parse(server).host;

  Map<String, String> toJson() =>
      {'id': id, 'kind': kind.name, 'server': server, 'username': username};

  static HostingAccount? fromJson(Map<String, dynamic> json) {
    final kind = HostingKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) return null;
    return HostingAccount(
      id: json['id'] as String,
      kind: kind,
      server: json['server'] as String,
      username: json['username'] as String,
    );
  }
}

/// A repository listed from a hosting account.
class RemoteRepo {
  const RemoteRepo({
    required this.fullName,
    required this.httpsUrl,
    required this.sshUrl,
    required this.webUrl,
    required this.description,
    required this.isPrivate,
  });

  final String fullName;
  final String httpsUrl;
  final String sshUrl;
  final String webUrl;
  final String description;
  final bool isPrivate;
}

class HostingException implements Exception {
  const HostingException(this.message);

  final String message;

  @override
  String toString() => message;
}

String normalizeServer(String server) {
  var s = server.trim();
  if (!s.contains('://')) s = 'https://$s';
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// Minimal REST client for the supported hosting services.
class HostingApi {
  HostingApi(this.kind, String server, this.token) : server = normalizeServer(server);

  final HostingKind kind;
  final String server;
  final String token;

  String get _apiBase {
    final isPublicGitHub = Uri.parse(server).host == 'github.com';
    return switch (kind) {
      HostingKind.github => isPublicGitHub ? 'https://api.github.com' : '$server/api/v3',
      HostingKind.gitlab => '$server/api/v4',
      HostingKind.gitea => '$server/api/v1',
      HostingKind.generic => throw const HostingException('This server has no API.'),
    };
  }

  Map<String, String> get _headers => switch (kind) {
        HostingKind.github => {
            'Authorization': 'Bearer $token',
            'Accept': 'application/vnd.github+json',
          },
        HostingKind.gitlab => {'PRIVATE-TOKEN': token},
        HostingKind.gitea => {'Authorization': 'token $token'},
        HostingKind.generic => const <String, String>{},
      };

  Future<dynamic> _get(String path) async {
    final client = NetworkSettings.httpClient();
    try {
      final request = await client.getUrl(Uri.parse('$_apiBase$path'));
      _headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.userAgentHeader, 'EasyGit');
      final response = await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const HostingException('The token was rejected. Check that it is valid and has the required scopes.');
      }
      if (response.statusCode >= 400) {
        throw HostingException('${kind.label} returned HTTP ${response.statusCode}.');
      }
      return jsonDecode(body);
    } on SocketException catch (e) {
      throw HostingException('Cannot reach $server: ${e.message}');
    } on HandshakeException catch (e) {
      throw HostingException('TLS error talking to $server: ${e.message}');
    } on FormatException {
      throw HostingException('Unexpected response from $server. Is the server URL correct?');
    } finally {
      client.close();
    }
  }

  /// Returns the login name of the token's owner.
  Future<String> verify() async {
    final user = await _get('/user');
    final login = switch (kind) {
      HostingKind.github || HostingKind.gitea => user['login'],
      HostingKind.gitlab => user['username'],
      HostingKind.generic => null,
    };
    if (login is! String || login.isEmpty) {
      throw const HostingException('Could not read the account name.');
    }
    return login;
  }

  /// Repositories the account owns or is a member of, most recent first.
  Future<List<RemoteRepo>> repositories({int maxPages = 5}) async {
    final repos = <RemoteRepo>[];
    for (var page = 1; page <= maxPages; page++) {
      final path = switch (kind) {
        HostingKind.github => '/user/repos?per_page=100&sort=updated&page=$page',
        HostingKind.gitlab =>
          '/projects?membership=true&simple=true&per_page=100&order_by=last_activity_at&page=$page',
        HostingKind.gitea => '/user/repos?limit=50&page=$page',
        HostingKind.generic => throw const HostingException('This server has no API.'),
      };
      final data = await _get(path);
      if (data is! List || data.isEmpty) break;
      for (final r in data.cast<Map<String, dynamic>>()) {
        repos.add(switch (kind) {
          HostingKind.github || HostingKind.gitea || HostingKind.generic => RemoteRepo(
              fullName: r['full_name'] as String? ?? '',
              httpsUrl: r['clone_url'] as String? ?? '',
              sshUrl: r['ssh_url'] as String? ?? '',
              webUrl: r['html_url'] as String? ?? '',
              description: r['description'] as String? ?? '',
              isPrivate: r['private'] == true,
            ),
          HostingKind.gitlab => RemoteRepo(
              fullName: r['path_with_namespace'] as String? ?? '',
              httpsUrl: r['http_url_to_repo'] as String? ?? '',
              sshUrl: r['ssh_url_to_repo'] as String? ?? '',
              webUrl: r['web_url'] as String? ?? '',
              description: r['description'] as String? ?? '',
              isPrivate: r['visibility'] != 'public',
            ),
        });
      }
      if (data.length < (kind == HostingKind.gitea ? 50 : 100)) break;
    }
    return repos;
  }

  /// Page where the user can create a token with the scopes EasyGit needs.
  static String tokenPage(HostingKind kind, String server) {
    final s = normalizeServer(server);
    return switch (kind) {
      HostingKind.github =>
        '$s/settings/tokens/new?scopes=repo,read:org,workflow&description=EasyGit',
      HostingKind.gitlab =>
        '$s/-/user_settings/personal_access_tokens?name=EasyGit&scopes=api,read_user,write_repository',
      HostingKind.gitea => '$s/user/settings/applications',
      HostingKind.generic => s,
    };
  }

  static String tokenScopesHint(HostingKind kind) => switch (kind) {
        HostingKind.github => 'Scopes: repo, read:org, workflow',
        HostingKind.gitlab => 'Scopes: api, read_user, write_repository',
        HostingKind.gitea => 'Permissions: repository (read & write), user (read)',
        HostingKind.generic => 'Use a personal access token, app password or your password.',
      };
}

/// Host and `owner/repo` path parsed from a git remote URL.
class RemoteLocation {
  const RemoteLocation(this.host, this.path);

  final String host;

  /// Repository path without `.git`, e.g. `owner/repo` or `group/sub/repo`.
  final String path;

  /// Parses https, ssh (`ssh://`) and scp-like (`git@host:owner/repo`) URLs.
  static RemoteLocation? parse(String url) {
    var u = url.trim();
    if (u.isEmpty) return null;
    String host;
    String path;
    final scp = RegExp(r'^(?:[^@/]+@)?([^:/]+):(?!//)(.+)$').firstMatch(u);
    if (!u.contains('://') && scp != null) {
      host = scp[1]!;
      path = scp[2]!;
    } else {
      final uri = Uri.tryParse(u);
      if (uri == null || uri.host.isEmpty) return null;
      host = uri.host;
      path = uri.path;
    }
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('.git')) path = path.substring(0, path.length - 4);
    if (path.isEmpty || !path.contains('/')) return null;
    return RemoteLocation(host.toLowerCase(), path);
  }
}

/// Web links for a repository on a hosting service.
class RepoWeb {
  const RepoWeb(this.kind, this.server, this.path);

  final HostingKind kind;
  final String server;
  final String path;

  String get home => '$server/$path';

  String commit(String hash) => switch (kind) {
        HostingKind.gitlab => '$home/-/commit/$hash',
        _ => '$home/commit/$hash',
      };

  String file(String rev, String file) => switch (kind) {
        HostingKind.github => '$home/blob/$rev/${_encodePath(file)}',
        HostingKind.gitlab => '$home/-/blob/$rev/${_encodePath(file)}',
        HostingKind.gitea => '$home/src/commit/$rev/${_encodePath(file)}',
        HostingKind.generic => home,
      };

  String branch(String name) => switch (kind) {
        HostingKind.github => '$home/tree/${_encodePath(name)}',
        HostingKind.gitlab => '$home/-/tree/${_encodePath(name)}',
        HostingKind.gitea => '$home/src/branch/${_encodePath(name)}',
        HostingKind.generic => home,
      };

  /// Page that starts a pull/merge request from [branch] into [base].
  String newRequest(String branch, {String? base}) => switch (kind) {
        HostingKind.github => base == null
            ? '$home/compare/${_encodePath(branch)}?expand=1'
            : '$home/compare/${_encodePath(base)}...${_encodePath(branch)}?expand=1',
        HostingKind.gitlab => '$home/-/merge_requests/new?'
            'merge_request%5Bsource_branch%5D=${Uri.encodeQueryComponent(branch)}'
            '${base == null ? '' : '&merge_request%5Btarget_branch%5D=${Uri.encodeQueryComponent(base)}'}',
        HostingKind.gitea =>
          '$home/compare/${_encodePath(base ?? 'main')}...${_encodePath(branch)}',
        HostingKind.generic => home,
      };

  static String _encodePath(String p) => p.split('/').map(Uri.encodeComponent).join('/');

  /// Resolves a remote URL to a known hosting service, preferring signed-in
  /// accounts (which also covers self-hosted servers).
  static RepoWeb? forRemote(String remoteUrl, List<HostingAccount> accounts) {
    final loc = RemoteLocation.parse(remoteUrl);
    if (loc == null) return null;
    for (final a in accounts) {
      // Generic servers have no known web UI layout; fall back to host detection.
      if (a.kind.hasApi && a.host.toLowerCase() == loc.host) {
        return RepoWeb(a.kind, a.server, loc.path);
      }
    }
    final kind = switch (loc.host) {
      'github.com' => HostingKind.github,
      'gitlab.com' => HostingKind.gitlab,
      'codeberg.org' || 'gitea.com' => HostingKind.gitea,
      final h when h.contains('github') => HostingKind.github,
      final h when h.contains('gitlab') => HostingKind.gitlab,
      final h when h.contains('gitea') || h.contains('forgejo') => HostingKind.gitea,
      _ => null,
    };
    if (kind == null) return null;
    return RepoWeb(kind, 'https://${loc.host}', loc.path);
  }
}
