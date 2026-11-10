import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/hosting/hosting.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/app_settings.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/state/repos_state.dart';
import 'package:easygit/ui/views/account_view.dart';
import 'package:easygit/ui/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ReposState> _state() async {
  SharedPreferences.setMockInitialValues({});
  final settings = AppSettings();
  await settings.load();
  return ReposState(settings, AccountsStore());
}

Future<void> _git(String dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir);
  if (result.exitCode != 0) throw StateError('git ${args.join(' ')}: ${result.stderr}');
}

void main() {
  testWidgets('choice dialog scrolls through many repositories', (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            selected = await showChoiceDialog<String>(
              context,
              title: 'Open Repository',
              message: 'Choose a repository:',
              options: [
                for (var i = 0; i < 50; i++)
                  ChoiceOption('repo-$i', 'Repository $i', '/tmp/repo-$i'),
              ],
              initial: 'repo-0',
              okLabel: 'Open',
            );
          },
          child: const Text('Choose'),
        ),
      ),
    ));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    await tester.drag(scrollable, const Offset(0, -2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repository 49'));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(selected, 'repo-49');
  });

  testWidgets('generic account repository list scrolls', (tester) async {
    final repos = await _state();
    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_scroll');
      await _git(tmp.path, ['init', '-b', 'main']);
      ctrl = RepoController(await GitRepository.open(tmp.path), repos.accounts);
      ctrl.remoteUrls = const {'origin': 'https://git.example.com/team/repo.git'};
      repos.repos.addAll(List.filled(30, ctrl));
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    const account = HostingAccount(
      id: 'generic:git.example.com:me',
      kind: HostingKind.generic,
      server: 'https://git.example.com',
      username: 'me',
    );
    await tester.pumpWidget(MaterialApp(
      home: AccountView(account: account, repos: repos),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: find.byType(AccountView),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);
    await tester.drag(scrollable, const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(find.text('Clone by URL...'), findsOneWidget);
  });
}
