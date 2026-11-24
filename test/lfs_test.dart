import 'dart:convert';
import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/git_runner.dart';
import 'package:easygit/git/lfs.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

class _LfsServer {
  _LfsServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_LfsServer> start() async =>
      _LfsServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final uploaded = <String, List<int>>{};

  String get origin => 'http://${_server.address.host}:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'POST' && path.endsWith('/locks/verify')) {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response
          .write(jsonEncode({'ours': <Object>[], 'theirs': <Object>[]}));
    } else if (request.method == 'POST' && path.endsWith('/objects/batch')) {
      final data = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      final objects = data['objects'] as List<dynamic>? ?? [];
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'transfer': 'basic',
        'objects': [
          for (final value in objects)
            {
              'oid': (value as Map<String, dynamic>)['oid'],
              'size': value['size'],
              'actions': {
                'upload': {'href': '$origin/upload/${value['oid']}'},
              },
            },
        ],
      }));
    } else if (request.method == 'PUT' && path.startsWith('/upload/')) {
      final bytes = await request.expand((chunk) => chunk).toList();
      uploaded[path.substring('/upload/'.length)] = bytes;
    } else {
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
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

    final attrs = parseCheckAttrZ(
        'a.bin\x00filter\x00lfs\x00b.txt\x00filter\x00unspecified\x00');
    expect(attrs['a.bin']!['filter'], 'lfs');
    expect(attrs['b.txt']!['filter'], 'unspecified');

    final env = LfsEnv.parse(
        'Endpoint=https://git.example.com/a.git/info/lfs (auth=none)\n'
        'LocalMediaDir=C:\\r\\.git\\lfs\\objects\n');
    expect(env.endpoint, 'https://git.example.com/a.git/info/lfs');
    expect(env.auth, 'none');
    expect(env.objectPath('abcdef'), r'C:\r\.git\lfs\objects/ab/cd/abcdef');
  });

  test('builds a sorted folder tree with recursive totals', () {
    LfsFile file(String path, int size) => LfsFile(
          path: path,
          size: size,
          oid: path,
          downloaded: true,
          checkedOut: true,
        );
    final tree = buildLfsTree([
      file('root.bin', 2),
      file('assets/b.bin', 5),
      file('assets/images/a.bin', 10),
    ]);

    expect(tree.fileCount, 3);
    expect(tree.totalSize, 17);
    expect(tree.children.map((n) => n.name), ['assets', 'root.bin']);
    final assets = tree.children.first;
    expect(assets.isFolder, isTrue);
    expect(assets.fileCount, 2);
    expect(assets.totalSize, 15);
    expect(assets.children.map((n) => n.name), ['images', 'b.bin']);
    expect(assets.children.first.files.single.path, 'assets/images/a.bin');
  });

  test('formats byte sizes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(3000000), '2.9 MB');
  });

  test('the server test uses the LFS credentials of its server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final authorizations = <String>[];
    final subscription = server.listen((request) async {
      final value = request.headers.value(HttpHeaders.authorizationHeader);
      if (value != null) authorizations.add(value);
      await request.drain<void>();
      request.response.statusCode = HttpStatus.ok;
      request.response.write('{}');
      await request.response.close();
    });
    try {
      final origin = 'http://${server.address.host}:${server.port}';
      final result = await testLfsServer('$origin/team/app',
          credential: GitCredential(origin, 'lfs-user', 'lfs-token'));
      expect(result.status, LfsServerStatus.ok);
      expect(authorizations,
          ['Basic ${base64Encode(utf8.encode('lfs-user:lfs-token'))}']);

      // A credential saved for another server is not sent.
      authorizations.clear();
      await testLfsServer('$origin/team/app',
          credential: const GitCredential('https://elsewhere.example.com', 'u', 't'));
      expect(authorizations, isEmpty);
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('real repository: tracking, files and LFS server source', () async {
    if (await GitRepository.lfsVersion() == null)
      return; // git-lfs not installed
    final tmp = await Directory.systemTemp.createTemp('easygit_lfs');
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));
    final dir = '${tmp.path}/repo'.replaceAll('\\', '/');
    await Directory(dir).create();
    await _git(dir, ['init', '-b', 'main']);
    await _git(dir, ['config', 'user.email', 't@example.com']);
    await _git(dir, ['config', 'user.name', 'Tester']);
    await _git(dir,
        ['remote', 'add', 'origin', 'https://git.example.com/team/app.git']);
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

  test('real repository: folder cleanup protects modified and unpushed content',
      () async {
    if (await GitRepository.lfsVersion() == null) {
      return; // git-lfs not installed
    }
    final tmp = await Directory.systemTemp.createTemp('easygit_lfs_clean');
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));
    final dir = '${tmp.path}/repo'.replaceAll('\\', '/');
    await Directory('$dir/assets/images').create(recursive: true);
    await Directory('$dir/assets/docs').create(recursive: true);
    await _git(dir, ['init', '-b', 'main']);
    await _git(dir, ['config', 'user.email', 't@example.com']);
    await _git(dir, ['config', 'user.name', 'Tester']);
    await _git(dir, ['config', 'lfs.pruneverifyremotealways', 'false']);
    await _git(dir,
        ['remote', 'add', 'origin', 'https://git.example.com/team/app.git']);
    await _git(dir, ['lfs', 'install', '--local']);

    final repo = await GitRepository.open(dir);
    await repo.lfsTrack(['*.bin']);
    await File('$dir/assets/images/a.bin').writeAsBytes(List.filled(4096, 7));
    await File('$dir/assets/docs/b.bin').writeAsBytes(List.filled(2048, 8));
    await _git(dir, ['add', '-A']);
    await _git(dir, ['commit', '-m', 'add assets']);

    final initial = await repo.lfsFiles();
    final a = initial.singleWhere((f) => f.path == 'assets/images/a.bin');
    final b = initial.singleWhere((f) => f.path == 'assets/docs/b.bin');
    final env = await repo.lfsEnv();
    final aObject = File(env.objectPath(a.oid)!);
    final bObject = File(env.objectPath(b.oid)!);
    expect(await aObject.exists(), isTrue);

    var result = await repo.lfsClean([a]);
    expect(result.cleaned, 1);
    expect(result.skipped, 0);
    expect(LfsPointer.parse(await File('$dir/${a.path}').readAsString())!.oid,
        a.oid);
    expect(await aObject.exists(), isTrue,
        reason: 'an unpushed object must be retained');

    await _git(dir, ['update-ref', 'refs/remotes/origin/main', 'HEAD']);
    final pointerA =
        (await repo.lfsFiles()).singleWhere((f) => f.path == a.path);
    expect(pointerA.checkedOut, isFalse);
    result = await repo.lfsClean([pointerA]);
    expect(result.cleaned, 1);
    expect(await aObject.exists(), isFalse);
    expect(await bObject.exists(), isTrue,
        reason: 'another folder must not be pruned');

    await File('$dir/${b.path}').writeAsBytes(List.filled(2048, 9));
    result = await repo.lfsClean([b], changedPaths: {b.path});
    expect(result.cleaned, 0);
    expect(result.skipped, 1);
    expect(await File('$dir/${b.path}').readAsBytes(), List.filled(2048, 9));
    expect(await bObject.exists(), isTrue);
  });

  test('parses LFS transfer progress', () {
    final progress = LfsTransferProgress.parse(
        'Uploading LFS objects:  42% (3/7), 12.5 MB | 2 MB/s')!;
    expect(progress.uploading, isTrue);
    expect(progress.percent, 42);
    expect(progress.fraction, closeTo(0.42, 0.001));
    expect(progress.completedFiles, 3);
    expect(progress.totalFiles, 7);
    expect(LfsTransferProgress.parse('Everything up-to-date'), isNull);
  });

  test('real repository: LFS upload and git push report progress', () async {
    if (await GitRepository.lfsVersion() == null) {
      return; // git-lfs not installed
    }
    final tmp = await Directory.systemTemp.createTemp('easygit_lfs_upload');
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));
    final server = await _LfsServer.start();
    addTearDown(server.close);
    final oldNetwork = GitRunner.networkEnv;
    GitRunner.networkEnv = const {
      'NO_PROXY': '127.0.0.1,localhost',
      'no_proxy': '127.0.0.1,localhost',
    };
    addTearDown(() => GitRunner.networkEnv = oldNetwork);

    final dir = '${tmp.path}/repo'.replaceAll('\\', '/');
    final remote = '${tmp.path}/remote.git'.replaceAll('\\', '/');
    await Directory(dir).create();
    await _git(tmp.path, ['init', '--bare', remote]);
    await _git(dir, ['init', '-b', 'main']);
    await _git(dir, ['config', 'user.email', 't@example.com']);
    await _git(dir, ['config', 'user.name', 'Tester']);
    await _git(dir, ['remote', 'add', 'origin', remote]);
    await _git(dir, ['config', 'lfs.url', '${server.origin}/info/lfs']);
    await _git(dir, ['lfs', 'install', '--local']);

    final repo = await GitRepository.open(dir);
    await repo.lfsTrack(['*.bin']);
    final aBytes = List<int>.filled(8 * 1024 * 1024, 7);
    await File('$dir/a.bin').writeAsBytes(aBytes);
    await _git(dir, ['add', '-A']);
    await _git(dir, ['commit', '-m', 'add a']);
    final a = (await repo.lfsFiles()).single;

    final output = <String>[];
    await repo.push(onProgress: output.add);
    final pushProgress = LfsTransferProgress.parse(output.join());
    expect(pushProgress, isNotNull, reason: output.join());
    expect(pushProgress!.uploading, isTrue);
    expect(server.uploaded[a.oid], aBytes);

    final bBytes = List<int>.filled(2 * 1024 * 1024, 8);
    await File('$dir/b.bin').writeAsBytes(bBytes);
    await _git(dir, ['add', '-A']);
    await _git(dir, ['commit', '-m', 'add b']);
    final b = (await repo.lfsFiles()).singleWhere((f) => f.path == 'b.bin');

    output.clear();
    await repo.lfsPush('origin', [b.oid], onProgress: output.add);
    expect(LfsTransferProgress.parse(output.join()), isNotNull,
        reason: output.join());
    expect(server.uploaded[b.oid], bBytes);
    expect((await repo.status()).ahead, 1,
        reason: 'uploading one object must not push the Git commit');
  });

}
