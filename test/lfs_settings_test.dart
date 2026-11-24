import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/lfs.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/lfs_credentials.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/theme/ide_theme.dart';
import 'package:easygit/ui/lfs/lfs_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  testWidgets('LFS settings show where the credentials come from',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_lfs_settings');
      final dir = tmp.path.replaceAll('\\', '/');
      await _git(dir, ['init', '-b', 'main']);
      await _git(dir,
          ['remote', 'add', 'origin', 'https://git.example.com/team/app.git']);
      ctrl = RepoController(await GitRepository.open(dir), AccountsStore());
      ctrl.lfs
        ..version = 'git-lfs/3.7.0'
        ..usesLfs = true
        ..hooksInstalled = true
        ..patterns = const ['*.psd']
        ..env = const LfsEnv(
            endpoint: 'https://git.example.com/team/app.git/info/lfs');
      ctrl.lfsCredential = const LfsCredential(
          server: 'https://lfs.example.com', username: 'lfs-bot', token: 'token');
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildIdeTheme(Brightness.light),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLfsDialog(context, ctrl),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Credentials'), findsOneWidget);
    expect(find.text('lfs-bot at https://lfs.example.com'), findsOneWidget);
    expect(find.textContaining('Saved for another server'), findsOneWidget);

    // The server section starts git in the background; let its timers run out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
  });
}
