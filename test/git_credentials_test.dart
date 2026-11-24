import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/git_runner.dart';
import 'package:easygit/git/models.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthServer {
  _AuthServer._(this._server) {
    _subscription = _server.listen(_handle);
  }

  static Future<_AuthServer> start() async =>
      _AuthServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  late final StreamSubscription<HttpRequest> _subscription;
  final authorizations = <String>[];

  String get origin => 'http://${_server.address.host}:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    final authorization = request.headers.value(HttpHeaders.authorizationHeader);
    if (authorization != null) authorizations.add(authorization);
    await request.drain<void>();
    if (authorization == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="EasyGit test"');
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }
}

void main() {
  setUp(() => GitRunner.networkEnv = const {
        'NO_PROXY': '127.0.0.1,localhost',
        'no_proxy': '127.0.0.1,localhost',
      });
  tearDown(() {
    GitRunner.credentials = const [];
    GitRunner.networkEnv = const {};
  });

  test('clone ignores credential helpers from Git configuration', () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_credentials');
    final server = await _AuthServer.start();
    try {
      final home = '${tmp.path}/home'.replaceAll('\\', '/');
      await Directory(home).create();
      await File('$home/.gitconfig').writeAsString(r'''
[credential]
    helper = !f() { test "$1" = get || return 0; echo username=system-user; echo password=system-pass; }; f
''');
      await expectLater(
        GitRunner(tmp.path).run(
          ['clone', '${server.origin}/owner/repo.git', 'repo'],
          env: {
            'HOME': home,
            'USERPROFILE': home,
            'XDG_CONFIG_HOME': '$home/.config',
            'GIT_CONFIG_NOSYSTEM': '1',
          },
        ),
        throwsA(isA<GitException>()),
      );
      expect(server.authorizations, isEmpty);
    } finally {
      await server.close();
      await tmp.delete(recursive: true);
    }
  });

  test('clone uses its explicitly selected account instead of the default', () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_clone_credentials');
    final server = await _AuthServer.start();
    try {
      GitRunner.credentials = [
        GitCredential(server.origin, 'default-user', 'default-token'),
      ];
      await expectLater(
        GitRepository.clone(
          '${server.origin}/owner/repo.git',
          tmp.path,
          'repo',
          credentials: [GitCredential(server.origin, 'selected-user', 'selected-token')],
        ),
        throwsA(isA<GitException>()),
      );
      final expected = base64Encode(utf8.encode('selected-user:selected-token'));
      expect(server.authorizations, ['Basic $expected']);
    } finally {
      await server.close();
      await tmp.delete(recursive: true);
    }
  });

  test('credentials answer once per server, LFS first for git lfs', () {
    const git = GitCredential('https://git.example.com', 'git-user', 'git-token');
    const lfs = GitCredential('https://lfs.example.com', 'lfs-user', 'lfs-token');

    // Different servers: both are configured, LFS first for `lfs` commands.
    var (config, env) = GitRunner.credentialArgs(['lfs', 'pull'], const [git],
        lfsCredentials: const [lfs]);
    expect(env['EASYGIT_USER_0'], 'lfs-user');
    expect(env['EASYGIT_USER_1'], 'git-user');
    expect(
        config.where((a) => a == 'credential.https://lfs.example.com.helper=').length,
        1);
    expect(
        config.where((a) => a == 'credential.https://git.example.com.helper=').length,
        1);

    // The other network commands prefer the account.
    (config, env) = GitRunner.credentialArgs(['push'], const [git],
        lfsCredentials: const [lfs]);
    expect(env['EASYGIT_USER_0'], 'git-user');
    expect(env['EASYGIT_USER_1'], 'lfs-user');
  });

  test('a server is answered by one credential only', () {
    const account = GitCredential('https://host.example.com', 'git-user', 'git-token');
    const own = GitCredential('https://host.example.com', 'lfs-user', 'lfs-token');

    var (config, env) =
        GitRunner.credentialArgs(['lfs', 'push'], const [account], lfsCredentials: const [own]);
    expect(env.length, 2, reason: 'one helper answers for the shared server');
    expect(env['EASYGIT_USER_0'], 'lfs-user');
    expect(config.where((a) => a == 'credential.https://host.example.com.helper=').length, 1);

    (config, env) = GitRunner.credentialArgs(['fetch'], const [account], lfsCredentials: const [own]);
    expect(env['EASYGIT_USER_0'], 'git-user');
  });

  test('commands that do not go to the network get no credentials', () {
    final (config, env) = GitRunner.credentialArgs(['status'], const [],
        lfsCredentials: const [GitCredential('https://lfs.example.com', 'u', 't')]);
    expect(config, isEmpty);
    expect(env, isEmpty);
  });

  test('LFS credentials authenticate their server', () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_lfs_credentials');
    final server = await _AuthServer.start();
    try {
      final runner = GitRunner(tmp.path)
        ..lfsCredentials = [GitCredential(server.origin, 'lfs-user', 'lfs-token')];
      await expectLater(
        runner.run(['ls-remote', '${server.origin}/owner/repo.git']),
        throwsA(isA<GitException>()),
      );
      final expected = base64Encode(utf8.encode('lfs-user:lfs-token'));
      expect(server.authorizations, ['Basic $expected']);
    } finally {
      await server.close();
      await tmp.delete(recursive: true);
    }
  });
}
