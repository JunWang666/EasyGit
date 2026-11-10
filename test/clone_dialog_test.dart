import 'package:easygit/hosting/hosting.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/ui/shell/clone_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHostingApi extends HostingApi {
  _FakeHostingApi(HostingAccount account)
      : username = account.username,
        super(account.kind, account.server, 'token');

  final String username;

  @override
  Future<List<RemoteRepo>> repositories({int maxPages = 5}) async => [
        RemoteRepo(
          fullName: '$username/private',
          httpsUrl: '$server/$username/private.git',
          sshUrl: 'git@github.com:$username/private.git',
          webUrl: '$server/$username/private',
          description: '',
          isPrivate: true,
        ),
      ];
}

class _FakeAccountsStore extends AccountsStore {
  _FakeAccountsStore(List<HostingAccount> values) {
    accounts = values;
  }

  @override
  HostingApi apiFor(HostingAccount account) => _FakeHostingApi(account);
}

void main() {
  testWidgets('clone request retains the selected account', (tester) async {
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
    final accounts = _FakeAccountsStore([first, second]);
    CloneRequest? request;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => request = await showCloneDialog(context, accounts),
          child: const Text('Open clone'),
        ),
      ),
    ));
    await tester.tap(find.text('Open clone'));
    await tester.pump();
    await tester.tap(find.text('GitHub: second'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('second/private'));
    await tester.pump();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(1), 'C:/tmp');
    await tester.tap(find.text('Clone'));
    await tester.pump();

    expect(request, isNotNull);
    expect(request!.url, 'https://github.com/second/private.git');
    expect(request!.folder, 'private');
    expect(request!.accountId, second.id);
  });
}
