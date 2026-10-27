import 'package:easygit/net/network.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Windows system proxy', () {
    test('single server', () {
      final p = parseWindowsProxy('''
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    ProxyEnable    REG_DWORD    0x1
    ProxyServer    REG_SZ    127.0.0.1:7890
    ProxyOverride    REG_SZ    localhost;127.*;<local>
''');
      expect(p.proxy!.url, 'http://127.0.0.1:7890');
      expect(p.proxy!.bypass, ['localhost', '127.*', '<local>']);
    });

    test('per-protocol servers prefer https, then socks', () {
      expect(
          parseWindowsProxy('    ProxyEnable    REG_DWORD    0x1\n'
                  '    ProxyServer    REG_SZ    http=a:1;https=b:2;socks=c:3\n')
              .proxy!
              .url,
          'http://b:2');
      expect(
          parseWindowsProxy('    ProxyEnable    REG_DWORD    0x1\n'
                  '    ProxyServer    REG_SZ    socks=c:3\n')
              .proxy!
              .url,
          'socks5h://c:3');
    });

    test('disabled proxy with a PAC script', () {
      final p = parseWindowsProxy('    ProxyEnable    REG_DWORD    0x0\n'
          '    AutoConfigURL    REG_SZ    http://wpad/proxy.pac\n');
      expect(p.proxy, isNull);
      expect(p.pacUrl, 'http://wpad/proxy.pac');
    });
  });

  test('macOS scutil output', () {
    final p = parseMacProxy('''
<dictionary> {
  ExceptionsList : <array> {
    0 : *.local
    1 : 169.254/16
  }
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
}''');
    expect(p.proxy!.url, 'http://127.0.0.1:7890');
    expect(p.proxy!.bypass, ['*.local', '169.254/16']);
  });

  test('network hints', () {
    expect(networkHint("fatal: unable to access 'x': Failed to connect to github.com:443 over proxy 127.0.0.1"),
        contains('proxy'));
    expect(networkHint('SSL certificate problem: self-signed certificate'), contains('certificate'));
    expect(networkHint('Could not resolve host: git.corp'), contains('resolved'));
    expect(networkHint('The requested URL returned error: 403'), contains('credentials'));
    expect(networkHint('error: pathspec abc401def did not match'), isNull);
  });

  group('git environment', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('git config mode changes nothing', () {
      expect(NetworkSettings().gitEnvironment(), isEmpty);
    });

    test('manual proxy with credentials and bypass', () async {
      final s = NetworkSettings();
      await s.save(
        mode: ProxyMode.manual,
        manualUrl: '127.0.0.1:7890',
        username: 'me',
        password: 'p@ss',
        bypass: 'localhost,.corp',
        bypassSelfHosted: true,
      );
      s.setSelfHostedHosts(['git.example.com']);
      final env = s.gitEnvironment();
      expect(env['GIT_CONFIG_KEY_0'], 'http.proxy');
      expect(env['GIT_CONFIG_VALUE_0'], 'http://me:p%40ss@127.0.0.1:7890');
      expect(env['NO_PROXY'], 'localhost,.corp,git.example.com');
    });

    test('no proxy overrides gitconfig and environment', () async {
      final s = NetworkSettings();
      await s.save(
        mode: ProxyMode.none,
        manualUrl: '',
        username: '',
        bypass: '',
        bypassSelfHosted: false,
      );
      final env = s.gitEnvironment();
      expect(env['GIT_CONFIG_VALUE_0'], '');
      expect(env['HTTPS_PROXY'], '');
    });
  });
}
