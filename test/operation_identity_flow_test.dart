import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/git_runner.dart';
import 'package:easygit/git/models.dart';
import 'package:easygit/hosting/hosting.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/theme/ide_theme.dart';
import 'package:easygit/ui/repo/operation_identity_flow.dart';
import 'package:easygit/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const first = HostingAccount(
  id: 'github:first',
  kind: HostingKind.github,
  server: 'https://github.com',
  username: 'first',
);
const second = HostingAccount(
  id: 'github:second',
  kind: HostingKind.github,
  server: 'https://github.com',
  username: 'second',
);

class _FakeAccountsStore extends AccountsStore {
  _FakeAccountsStore() {
    accounts = const [first, second];
  }

  HostingAccount? preferred;

  @override
  List<GitCredential>? credentialsPreferring(HostingAccount account) {
    preferred = account;
    return [GitCredential(account.server, account.username, 'token')];
  }
}

Future<String> _git(String dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
  return result.stdout as String;
}

Future<
    ({
      Directory tmp,
      String work,
      String remote,
      RepoController ctrl,
      _FakeAccountsStore accounts
    })> _repository() async {
  final tmp =
      await Directory.systemTemp.createTemp('easygit_operation_identity');
  final work = '${tmp.path}/work'.replaceAll('\\', '/');
  final remote = '${tmp.path}/remote.git'.replaceAll('\\', '/');
  await Directory(work).create();
  await _git(tmp.path, ['init', '--bare', remote]);
  await _git(work, ['init', '-b', 'main']);
  await _git(work, ['config', 'user.name', 'Default User']);
  await _git(work, ['config', 'user.email', 'default@example.com']);
  await _git(work, ['remote', 'add', 'origin', remote]);
  final accounts = _FakeAccountsStore();
  final ctrl = RepoController(await GitRepository.open(work), accounts);
  return (tmp: tmp, work: work, remote: remote, ctrl: ctrl, accounts: accounts);
}

void main() {
  testWidgets(
      'operation dialogs return the chosen commit identity and push account',
      (tester) async {
    late ({
      Directory tmp,
      String work,
      String remote,
      RepoController ctrl,
      _FakeAccountsStore accounts
    }) repo;
    await tester.runAsync(() async => repo = await _repository());
    addTearDown(() async {
      repo.ctrl.dispose();
      await repo.tmp.delete(recursive: true).catchError((_) => repo.tmp);
    });

    CommitOperationChoice? commitChoice;
    PushAccountChoice? pushChoice;
    await tester.pumpWidget(MaterialApp(
      theme: buildIdeTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Column(children: [
          TextButton(
            onPressed: () async =>
                commitChoice = await showDialog<CommitOperationChoice>(
              context: context,
              builder: (context) => CommitOperationDialog(
                ctrl: repo.ctrl,
                identity: const RepoIdentity(
                  localName: 'Default User',
                  localEmail: 'default@example.com',
                ),
                andPush: true,
              ),
            ),
            child: const Text('Open commit'),
          ),
          TextButton(
            onPressed: () async =>
                pushChoice = await showPushAccountDialog(context, repo.ctrl),
            child: const Text('Open push'),
          ),
        ]),
      ),
    ));

    await tester.tap(find.text('Open commit'));
    await tester.pumpAndSettle();
    expect(find.text('Commit identity'), findsOneWidget);
    expect(find.text('Push account'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.at(0)).controller!.text,
        'Default User');
    expect(tester.widget<TextField>(fields.at(1)).controller!.text,
        'default@example.com');
    await tester.enterText(fields.at(0), 'Second User');
    await tester.enterText(fields.at(1), 'second@example.com');
    await tester.tap(find.text('second'));
    await tester.pump();
    await tester.tap(find.widgetWithText(IdeButton, 'Commit and Push'));
    await tester.pumpAndSettle();

    expect(commitChoice?.name, 'Second User');
    expect(commitChoice?.email, 'second@example.com');
    expect(commitChoice?.accountId, second.id);

    await tester.tap(find.text('Open push'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the account used to authenticate this push.'),
        findsOneWidget);
    await tester.tap(find.text('first'));
    await tester.pump();
    await tester.tap(find.widgetWithText(IdeButton, 'Push'));
    await tester.pumpAndSettle();

    expect(pushChoice?.account?.id, first.id);
  });

  test('commit and standalone push use the chosen identity and account',
      () async {
    final repo = await _repository();
    try {
      await File('${repo.work}/a.txt').writeAsString('one\n');
      await repo.ctrl.refreshStatus();
      repo.ctrl.included.add('a.txt');
      repo.ctrl.messageController.text = 'chosen identity';

      await repo.ctrl.commit(
        andPush: true,
        authorName: 'Second User',
        authorEmail: 'second@example.com',
        pushAccount: second,
      );

      expect(repo.accounts.preferred?.id, second.id);
      expect(repo.ctrl.notifications.where((n) => n.isError), isEmpty,
          reason: [
            for (final n in repo.ctrl.notifications) '${n.title}: ${n.message}'
          ].join('\n'));
      final identity = (await _git(repo.work, [
        'log',
        '-1',
        '--format=%an%x00%ae%x00%cn%x00%ce',
      ]))
          .trim()
          .split('\x00');
      expect(identity, [
        'Second User',
        'second@example.com',
        'Second User',
        'second@example.com'
      ]);
      final configured = await repo.ctrl.repo.identity();
      expect(configured.localName, 'Default User');
      expect(configured.localEmail, 'default@example.com');
      final localHash = (await _git(repo.work, ['rev-parse', 'HEAD'])).trim();
      final remoteHash = (await _git(
              repo.tmp.path, ['--git-dir', repo.remote, 'rev-parse', 'main']))
          .trim();
      expect(remoteHash, localHash);

      await File('${repo.work}/b.txt').writeAsString('two\n');
      await _git(repo.work, ['add', 'b.txt']);
      await _git(repo.work, ['commit', '-m', 'standalone push']);
      await repo.ctrl.refreshAll();
      repo.accounts.preferred = null;
      await repo.ctrl.push(account: first);
      expect(repo.accounts.preferred?.id, first.id);
      expect(repo.ctrl.notifications.where((n) => n.isError), isEmpty);
    } finally {
      repo.ctrl.dispose();
      await repo.tmp.delete(recursive: true);
    }
  });

  test('a chosen identity replaces the author when amending', () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_amend_identity');
    try {
      final dir = tmp.path.replaceAll('\\', '/');
      await _git(dir, ['init', '-b', 'main']);
      await _git(dir, ['config', 'user.name', 'Default User']);
      await _git(dir, ['config', 'user.email', 'default@example.com']);
      await File('$dir/a.txt').writeAsString('one\n');
      await _git(dir, ['add', 'a.txt']);
      await _git(dir, ['commit', '-m', 'initial']);
      await File('$dir/a.txt').writeAsString('two\n');
      final repo = await GitRepository.open(dir);

      await repo.commit(
        'amended',
        const [
          FileChange(path: 'a.txt', kind: ChangeKind.modified, unstaged: true)
        ],
        amend: true,
        authorName: 'Second User',
        authorEmail: 'second@example.com',
      );

      final identity = (await _git(dir, [
        'log',
        '-1',
        '--format=%an%x00%ae%x00%cn%x00%ce',
      ]))
          .trim()
          .split('\x00');
      expect(identity, [
        'Second User',
        'second@example.com',
        'Second User',
        'second@example.com'
      ]);
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}
