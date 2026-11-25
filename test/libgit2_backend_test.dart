import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/libgit2_backend.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  test('libgit2 backend matches the CLI backend for status, refs and log',
      () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_backend');
    addTearDown(() => tmp.delete(recursive: true));
    await git(tmp.path, ['init', '-b', 'master']);
    await git(tmp.path, ['config', 'user.email', 'test@example.com']);
    await git(tmp.path, ['config', 'user.name', 'Test']);
    await File('${tmp.path}/a.txt').writeAsString('one\n');
    await git(tmp.path, ['add', '.']);
    await git(tmp.path, ['commit', '-m', 'first']);
    await File('${tmp.path}/a.txt').writeAsString('one\ntwo\n');
    await git(tmp.path, ['commit', '-am', 'second']);
    await File('${tmp.path}/a.txt').writeAsString('one\ntwo\nthree\n');
    await File('${tmp.path}/new.txt').writeAsString('new\n');

    final cli = await GitRepository.open(tmp.path);
    final native = await Libgit2Backend.open(tmp.path);

    final cliStatus = await cli.status();
    final nativeStatus = await native.status();
    expect(nativeStatus.branch, cliStatus.branch);
    expect(nativeStatus.headHash, cliStatus.headHash);
    expect(nativeStatus.changes.map((c) => c.path).toList(),
        cliStatus.changes.map((c) => c.path).toList());
    expect(nativeStatus.changes.map((c) => c.kind).toList(),
        cliStatus.changes.map((c) => c.kind).toList());

    final cliLog = await cli.log();
    final nativeLog = await native.log();
    expect(nativeLog.map((c) => c.hash).toList(),
        cliLog.map((c) => c.hash).toList());
    expect(nativeLog.map((c) => c.subject).toList(),
        cliLog.map((c) => c.subject).toList());
    expect(nativeLog.first.refs.any((r) => r.name == 'master'), isTrue);

    final cliRefs = await cli.refs();
    final nativeRefs = await native.refs();
    expect(nativeRefs.map((r) => r.fullName).toSet(),
        cliRefs.map((r) => r.fullName).toSet());

    expect(await native.fileAt('HEAD', 'a.txt'), 'one\ntwo\n');
    expect(await native.readWorkingFile('new.txt'), 'new\n');
    expect(native.name, cli.name);
  });
}
