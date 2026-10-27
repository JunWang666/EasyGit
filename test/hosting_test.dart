import 'package:easygit/hosting/hosting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteLocation.parse', () {
    test('https with .git', () {
      final l = RemoteLocation.parse('https://github.com/owner/repo.git')!;
      expect(l.host, 'github.com');
      expect(l.path, 'owner/repo');
    });

    test('scp-like ssh', () {
      final l = RemoteLocation.parse('git@gitlab.com:group/sub/repo.git')!;
      expect(l.host, 'gitlab.com');
      expect(l.path, 'group/sub/repo');
    });

    test('ssh:// with port and user', () {
      final l = RemoteLocation.parse('ssh://git@git.example.com:2222/team/app.git')!;
      expect(l.host, 'git.example.com');
      expect(l.path, 'team/app');
    });

    test('https with credentials in the URL', () {
      final l = RemoteLocation.parse('https://user@codeberg.org/me/thing/')!;
      expect(l.host, 'codeberg.org');
      expect(l.path, 'me/thing');
    });

    test('rejects local paths and junk', () {
      expect(RemoteLocation.parse(''), isNull);
      expect(RemoteLocation.parse('/srv/git/repo.git'), isNull);
    });
  });

  group('RepoWeb', () {
    test('detects public hosts', () {
      expect(RepoWeb.forRemote('git@github.com:a/b.git', const [])!.kind, HostingKind.github);
      expect(RepoWeb.forRemote('https://gitlab.com/a/b', const [])!.kind, HostingKind.gitlab);
      expect(RepoWeb.forRemote('https://codeberg.org/a/b', const [])!.kind, HostingKind.gitea);
      expect(RepoWeb.forRemote('https://example.com/a/b', const []), isNull);
    });

    test('self-hosted servers resolve through accounts', () {
      const account = HostingAccount(
          id: 'x', kind: HostingKind.gitlab, server: 'https://code.corp.net', username: 'me');
      final web = RepoWeb.forRemote('git@code.corp.net:team/app.git', [account])!;
      expect(web.kind, HostingKind.gitlab);
      expect(web.home, 'https://code.corp.net/team/app');
    });

    test('builds provider-specific links', () {
      const gh = RepoWeb(HostingKind.github, 'https://github.com', 'o/r');
      const gl = RepoWeb(HostingKind.gitlab, 'https://gitlab.com', 'g/r');
      expect(gh.commit('abc'), 'https://github.com/o/r/commit/abc');
      expect(gl.commit('abc'), 'https://gitlab.com/g/r/-/commit/abc');
      expect(gh.file('abc', 'lib/a b.dart'), 'https://github.com/o/r/blob/abc/lib/a%20b.dart');
      expect(gh.newRequest('feature/x', base: 'main'),
          'https://github.com/o/r/compare/main...feature/x?expand=1');
      expect(gl.newRequest('feat'),
          'https://gitlab.com/g/r/-/merge_requests/new?merge_request%5Bsource_branch%5D=feat');
    });
  });

  test('normalizeServer', () {
    expect(normalizeServer('gitlab.example.com/'), 'https://gitlab.example.com');
    expect(normalizeServer('http://h:8080'), 'http://h:8080');
  });
}
