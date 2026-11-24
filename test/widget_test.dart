import 'dart:io';

import 'package:easygit/git/lfs.dart';
import 'package:easygit/main.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/app_settings.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/state/repos_state.dart';
import 'package:easygit/system/open_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ReposState> _state() async {
  SharedPreferences.setMockInitialValues({});
  final settings = AppSettings();
  await settings.load();
  return ReposState(settings, AccountsStore());
}

void _bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _git(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  testWidgets('empty state renders', (tester) async {
    _bigWindow(tester);
    final repos = await _state();
    await tester.pumpWidget(EasyGitApp(
        settings: repos.settings,
        repos: repos,
        openRequests: OpenRequests(const [])));
    await tester.pump();

    expect(find.text('Welcome to EasyGit'), findsOneWidget);
    expect(find.text('Clone Repository'), findsOneWidget);
    expect(find.text('REPOSITORIES'), findsOneWidget);
    expect(find.text('ONLINE ACCOUNTS'), findsOneWidget);
  });

  testWidgets('a real repository shows in the sidebar and in every tab',
      (tester) async {
    _bigWindow(tester);
    final repos = await _state();
    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_test');
      final dir = '${tmp.path}/demo'.replaceAll('\\', '/');
      await Directory(dir).create();
      await _git(dir, ['init', '-b', 'main']);
      await _git(dir, ['config', 'user.email', 't@example.com']);
      await _git(dir, ['config', 'user.name', 'Tester']);
      await File('$dir/a.txt').writeAsString('one\n');
      await _git(dir, ['add', '.']);
      await _git(dir, ['commit', '-m', 'first commit']);
      await _git(dir, [
        'worktree',
        'add',
        '-b',
        'feature',
        '${tmp.path}/demo-feature'.replaceAll('\\', '/')
      ]);
      await File('$dir/a.txt').writeAsString('one\ntwo\n');
      ctrl = await repos.open(dir);
      await ctrl.refreshAll();
    });
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));

    await tester.pumpWidget(EasyGitApp(
        settings: repos.settings,
        repos: repos,
        openRequests: OpenRequests(const [])));
    await tester.pump();

    expect(ctrl.status!.changes.single.path, 'a.txt');
    expect(ctrl.worktrees.length, 2);
    expect(find.text('demo'), findsWidgets);
    // The sidebar no longer lists branches; they live in the Branches tab.
    expect(find.text('BRANCHES'), findsNothing);
    for (final v in RepoView.values) {
      expect(find.text(v.label), findsWidgets);
    }

    ctrl.setView(RepoView.history);
    await tester.pump();
    expect(find.text('first commit'), findsWidgets);

    ctrl.setView(RepoView.branches);
    await tester.pump();
    expect(find.text('feature'), findsWidgets);
    expect(find.text('current'), findsOneWidget);

    ctrl.setView(RepoView.worktrees);
    await tester.pump();
    expect(find.text('demo-feature'), findsOneWidget);
    expect(find.text('this window'), findsOneWidget);

    ctrl.remoteUrls = {'origin': 'https://git.example.com/team/app.git'};
    ctrl.lfs
      ..version = 'git-lfs/test'
      ..usesLfs = true
      ..files = {
        'assets/a.bin': const LfsFile(
          path: 'assets/a.bin',
          size: 4096,
          oid: 'abc',
          downloaded: false,
          checkedOut: false,
        ),
        'assets/b.bin': const LfsFile(
          path: 'assets/b.bin',
          size: 2048,
          oid: 'def',
          downloaded: true,
          checkedOut: true,
        ),
      };
    ctrl.notifyListeners();
    ctrl.setView(RepoView.lfs);
    await tester.pump();
    expect(find.text('LFS Settings...'), findsOneWidget);
    expect(find.text('assets'), findsOneWidget);
    expect(find.text('a.bin'), findsNothing);

    await tester.tap(find.text('assets'));
    await tester.pump();
    expect(find.text('a.bin'), findsOneWidget);
    expect(find.byTooltip('Download a.bin'), findsOneWidget);
    expect(find.byTooltip('Upload b.bin'), findsOneWidget);

    ctrl.busy = 'Uploading LFS files';
    ctrl.transferProgress = const LfsTransferProgress(
      uploading: true,
      percent: 42,
      completedFiles: 1,
      totalFiles: 2,
    );
    ctrl.notifyListeners();
    await tester.pump();
    expect(find.text('Uploading 42% · 1/2 files'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    ctrl.busy = null;
    ctrl.transferProgress = null;
    ctrl.notifyListeners();

    ctrl.setView(RepoView.files);
    await tester.pump();
    expect(find.text('Repository Files'), findsOneWidget);
    for (final path in [
      '.gitignore',
      '.gitattributes',
      '.lfsconfig',
      'README.md',
      '.editorconfig'
    ]) {
      expect(find.text(path), findsOneWidget);
    }
    expect(find.text('New File...'), findsOneWidget);

    ctrl.setView(RepoView.stashes);
    await tester.pump();
    expect(find.text('No stashes'), findsOneWidget);
    expect([for (final n in ctrl.notifications) '${n.title}: ${n.message}'],
        isEmpty);

    // Let tooltip and notification timers run out.
    await tester.pump(const Duration(seconds: 15));
  });
}
