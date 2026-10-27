import 'dart:io';

import 'package:easygit/main.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/app_settings.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/state/repos_state.dart';
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
    await tester.pumpWidget(EasyGitApp(settings: repos.settings, repos: repos));
    await tester.pump();

    expect(find.text('Welcome to EasyGit'), findsOneWidget);
    expect(find.text('Clone Repository'), findsOneWidget);
    expect(find.text('REPOSITORIES'), findsOneWidget);
    expect(find.text('ONLINE ACCOUNTS'), findsOneWidget);
  });

  testWidgets('a real repository shows in the sidebar and in every tab', (tester) async {
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
      await _git(dir, ['worktree', 'add', '-b', 'feature', '${tmp.path}/demo-feature'.replaceAll('\\', '/')]);
      await File('$dir/a.txt').writeAsString('one\ntwo\n');
      ctrl = await repos.open(dir);
      await ctrl.refreshAll();
    });
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));

    await tester.pumpWidget(EasyGitApp(settings: repos.settings, repos: repos));
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

    ctrl.setView(RepoView.stashes);
    await tester.pump();
    expect(find.text('No stashes'), findsOneWidget);
    expect([for (final n in ctrl.notifications) '${n.title}: ${n.message}'], isEmpty);

    // Let tooltip and notification timers run out.
    await tester.pump(const Duration(seconds: 15));
  });
}
