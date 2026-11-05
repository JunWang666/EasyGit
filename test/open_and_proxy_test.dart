import 'dart:io';

import 'package:easygit/net/network.dart';
import 'package:easygit/ui/shell/repo_flows.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _config(Map<String, String> env) => {
      for (var i = 0; i < int.parse(env['GIT_CONFIG_COUNT'] ?? '0'); i++)
        env['GIT_CONFIG_KEY_$i']!: env['GIT_CONFIG_VALUE_$i']!,
    };

void main() {
  group('proxy rules', () {
    test('match hosts and wildcards', () {
      expect(const ProxyRule('github.com', '').matches('github.com'), isTrue);
      expect(const ProxyRule('github.com', '').matches('api.github.com'), isFalse);
      expect(const ProxyRule('*.corp.example', '').matches('git.corp.example'), isTrue);
      expect(const ProxyRule('*.corp.example', '').matches('corp.example'), isFalse);
    });

    test('become per-URL git config on top of the mode', () {
      final net = NetworkSettings()
        ..mode = ProxyMode.manual
        ..manualUrl = 'http://127.0.0.1:7890'
        ..rules = const [
          ProxyRule('github.com', 'http://127.0.0.1:1080'),
          ProxyRule('git.corp.example', ''),
        ];
      final config = _config(net.gitEnvironment());
      expect(config['http.proxy'], 'http://127.0.0.1:7890');
      expect(config['http.https://github.com.proxy'], 'http://127.0.0.1:1080');
      expect(config['http.https://git.corp.example.proxy'], '');
      expect(config['http.http://git.corp.example.proxy'], '');
    });

    test('apply when git configuration is in charge', () {
      final net = NetworkSettings()..rules = const [ProxyRule('gitlab.com', 'socks5h://h:1')];
      expect(_config(net.gitEnvironment()), {
        'http.https://gitlab.com.proxy': 'socks5h://h:1',
        'http.http://gitlab.com.proxy': 'socks5h://h:1',
      });
    });
  });

  test('finds repositories below a folder, not inside them', () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_find');
    addTearDown(() => tmp.delete(recursive: true));
    Future<void> repo(String rel) => Directory('${tmp.path}/$rel/.git').create(recursive: true);
    await repo('a');
    await repo('group/b');
    await repo('a/nested'); // inside a: not reported
    await repo('x/y/too-deep');
    await Directory('${tmp.path}/node_modules/pkg/.git').create(recursive: true);
    final found = await findRepositoriesBelow(tmp.path);
    expect(found.map((p) => p.substring(tmp.path.length + 1).replaceAll('\\', '/')),
        ['a', 'group/b']);
  });
}
