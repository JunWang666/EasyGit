import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/lfs.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  test('parses LFS pointers', () {
    const text = 'version https://git-lfs.github.com/spec/v1\n'
        'oid sha256:1ae911889e9b8cb5de05085100dfb8e51ac41089d6e1c2460b37fc0f214502cd\n'
        'size 3000000\n';
    final p = LfsPointer.parse(text)!;
    expect(p.size, 3000000);
    expect(p.oid, startsWith('1ae9118'));
    expect(LfsPointer.parse('hello'), isNull);
  });

  test('parses ls-files json, check-attr and lfs env', () {
    final files = parseLfsFilesJson(
        '{"files":[{"name":"a.bin","size":5,"checkout":false,"downloaded":true,"oid":"ab"}]}');
    expect(files.single.path, 'a.bin');
    expect(files.single.downloaded, isTrue);
    expect(files.single.checkedOut, isFalse);

    final attrs = parseCheckAttrZ('a.bin\x00filter\x00lfs\x00b.txt\x00filter\x00unspecified\x00');
    expect(attrs['a.bin']!['filter'], 'lfs');
    expect(attrs['b.txt']!['filter'], 'unspecified');

    final env = LfsEnv.parse('Endpoint=https://git.example.com/a.git/info/lfs (auth=none)\n'
        'LocalMediaDir=C:\\r\\.git\\lfs\\objects\n');
    expect(env.endpoint, 'https://git.example.com/a.git/info/lfs');
    expect(env.auth, 'none');
    expect(env.objectPath('abcdef'), r'C:\r\.git\lfs\objects/ab/cd/abcdef');
  });

  test('formats byte sizes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(3000000), '2.9 MB');
  });

  test('real repository: tracking, files and LFS server source', () async {
    if (await GitRepository.lfsVersion() == null) return; // git-lfs not installed
    final tmp = await Directory.systemTemp.createTemp('easygit_lfs');
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));
    final dir = '${tmp.path}/repo'.replaceAll('\\', '/');
    await Directory(dir).create();
    await _git(dir, ['init', '-b', 'main']);
    await _git(dir, ['config', 'user.email', 't@example.com']);
    await _git(dir, ['config', 'user.name', 'Tester']);
    await _git(dir, ['remote', 'add', 'origin', 'https://git.example.com/team/app.git']);
    await _git(dir, ['lfs', 'install', '--local']);

    final repo = await GitRepository.open(dir);
    expect(await repo.usesLfs(), isFalse);
    await repo.lfsTrack(['*.bin']);
    expect(await repo.usesLfs(), isTrue);
    expect(await repo.lfsPatterns(), ['*.bin']);

    await File('$dir/big.bin').writeAsBytes(List.filled(4096, 7));
    await File('$dir/a.txt').writeAsString('text\n');
    expect(await repo.lfsTrackedPaths(['big.bin', 'a.txt']), {'big.bin'});
    await _git(dir, ['add', '-A']);
    await _git(dir, ['commit', '-m', 'add']);

    final files = await repo.lfsFiles();
    expect(files.single.path, 'big.bin');
    expect(files.single.size, 4096);
    expect(await repo.lfsHooksInstalled(), isTrue);
    // The committed blob is a pointer.
    expect(LfsPointer.parse(await repo.fileAt('HEAD', 'big.bin'))!.size, 4096);

    var config = await repo.lfsServerConfig();
    expect(config.source, LfsUrlSource.automatic);
    expect(config.effective, 'https://git.example.com/team/app.git/info/lfs');

    await repo.setLfsServer(LfsUrlSource.shared, 'https://lfs.example.com/app');
    config = await repo.lfsServerConfig();
    expect(config.source, LfsUrlSource.shared);
    expect(config.effective, 'https://lfs.example.com/app');

    await repo.setLfsServer(LfsUrlSource.local, 'https://mine.example.com/app');
    config = await repo.lfsServerConfig();
    expect(config.source, LfsUrlSource.local);
    expect(config.effective, 'https://mine.example.com/app');

    await repo.setLfsServer(LfsUrlSource.automatic, '');
    config = await repo.lfsServerConfig();
    expect(config.source, LfsUrlSource.automatic);
    expect(await File('$dir/.lfsconfig').exists(), isFalse);
  });
}
