import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/hosting/hosting.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/theme/ide_theme.dart';
import 'package:easygit/ui/repo/repo_settings_view.dart';
import 'package:easygit/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = HostingAccount(
  id: 'github:first',
  kind: HostingKind.github,
  server: 'https://github.com',
  username: 'first',
);
const _second = HostingAccount(
  id: 'github:second',
  kind: HostingKind.github,
  server: 'https://github.com',
  username: 'second',
);

class _Accounts extends AccountsStore {
  _Accounts() {
    accounts = const [_first, _second];
  }
}

Future<void> _git(String dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

void main() {
  testWidgets('repository settings save the default identity and account',
      (tester) async {
    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_repo_settings');
      await _git(tmp.path, ['init', '-b', 'main']);
      await _git(tmp.path, ['config', 'user.name', 'Default User']);
      await _git(tmp.path, ['config', 'user.email', 'default@example.com']);
      ctrl = RepoController(await GitRepository.open(tmp.path), _Accounts());
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildIdeTheme(Brightness.dark),
        home: Scaffold(body: RepoSettingsView(ctrl: ctrl)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.text('Repository Settings'), findsOneWidget);
    expect(find.text('Default commit identity'), findsOneWidget);
    expect(find.text('Default fetch and push account'), findsOneWidget);
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    expect(tester.widget<TextField>(fields.at(0)).controller!.text,
        'Default User');
    expect(tester.widget<TextField>(fields.at(1)).controller!.text,
        'default@example.com');

    await tester.enterText(fields.at(0), 'Repository User');
    await tester.enterText(fields.at(1), 'repository@example.com');
    await tester.tap(find.text('second'));
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(IdeButton, 'Save Defaults'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(IdeButton, 'Save Defaults'));
      for (var i = 0; i < 30 && ctrl.accountId != _second.id; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();

    expect(find.text('Defaults saved'), findsOneWidget);
    expect(ctrl.account?.id, _second.id);
    await tester.runAsync(() async {
      final identity = await ctrl.repo.identity();
      expect(identity.localName, 'Repository User');
      expect(identity.localEmail, 'repository@example.com');
      expect(await ctrl.repo.accountId(), _second.id);
    });
  });
}
