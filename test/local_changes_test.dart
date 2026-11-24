import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/models.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/theme/ide_theme.dart';
import 'package:easygit/ui/commit/commit_panel.dart';
import 'package:easygit/ui/diff/diff_view.dart';
import 'package:easygit/ui/views/repo_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _git(String dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

void main() {
  testWidgets('Local Changes folder tree collapses and checks folders',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_local_changes');
      await _git(tmp.path, ['init', '-b', 'main']);
      ctrl =
          RepoController(await GitRepository.open(tmp.path), AccountsStore());
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    ctrl.status = const RepoStatus(
      branch: 'main',
      headHash: 'abc',
      upstream: null,
      ahead: 0,
      behind: 0,
      state: RepoState.normal,
      changes: [
        FileChange(path: 'README.md', kind: ChangeKind.modified),
        FileChange(path: 'lib/a.dart', kind: ChangeKind.modified),
        FileChange(path: 'lib/src/b.dart', kind: ChangeKind.added),
        FileChange(path: 'docs/new.md', kind: ChangeKind.untracked),
      ],
    );
    ctrl.included.add('lib/a.dart');

    await tester.pumpWidget(MaterialApp(
      theme: buildIdeTheme(Brightness.dark),
      home: Scaffold(body: CommitPanel(ctrl: ctrl)),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('folder:changes:lib')), findsNothing);
    expect(find.text('a.dart  lib', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('Show Folder Tree'));
    await tester.pump();

    expect(find.byKey(const ValueKey('folder:changes:lib')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('folder:changes:lib/src')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('folder:unversioned:docs')), findsOneWidget);
    expect(find.text('a.dart', findRichText: true), findsOneWidget);
    expect(find.text('b.dart', findRichText: true), findsOneWidget);
    expect(find.text('new.md', findRichText: true), findsOneWidget);

    final libFolder = find.byKey(const ValueKey('folder:changes:lib'));
    await tester.tap(libFolder);
    await tester.pump();
    expect(find.text('a.dart', findRichText: true), findsNothing);
    expect(find.text('b.dart', findRichText: true), findsNothing);
    expect(find.byKey(const ValueKey('folder:changes:lib/src')), findsNothing);
    expect(find.text('new.md', findRichText: true), findsOneWidget);

    await tester.tap(libFolder);
    await tester.pump();
    final folderCheckbox =
        find.descendant(of: libFolder, matching: find.byType(Checkbox));
    expect(tester.widget<Checkbox>(folderCheckbox).value, isNull);
    await tester.tap(folderCheckbox);
    await tester.pump();

    expect(ctrl.included, containsAll(['lib/a.dart', 'lib/src/b.dart']));
    expect(find.text('a.dart', findRichText: true), findsOneWidget);
    expect(tester.widget<Checkbox>(folderCheckbox).value, isTrue);

    await tester.tap(folderCheckbox);
    await tester.pump();
    expect(ctrl.included.contains('lib/a.dart'), isFalse);
    expect(ctrl.included.contains('lib/src/b.dart'), isFalse);

    await tester.tap(find.byTooltip('Show Flat List'));
    await tester.pump();
    expect(find.byKey(const ValueKey('folder:changes:lib')), findsNothing);
    expect(find.text('a.dart  lib', findRichText: true), findsOneWidget);
    expect(find.text('b.dart  lib/src', findRichText: true), findsOneWidget);
  });

  testWidgets('Local Changes preview closes and reopens on file selection',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_close_preview');
      await _git(tmp.path, ['init', '-b', 'main']);
      await _git(tmp.path, ['config', 'user.email', 't@example.com']);
      await _git(tmp.path, ['config', 'user.name', 'Tester']);
      await Directory('${tmp.path}/lib').create();
      await File('${tmp.path}/lib/a.dart').writeAsString('one\n');
      await _git(tmp.path, ['add', '.']);
      await _git(tmp.path, ['commit', '-m', 'initial']);
      await File('${tmp.path}/lib/a.dart').writeAsString('one\ntwo\n');
      ctrl =
          RepoController(await GitRepository.open(tmp.path), AccountsStore());
      await ctrl.refreshStatus();
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    DiffTab memoryDiff() => DiffTab(
          id: 'wt:lib/a.dart',
          change: ctrl.status!.changes.single,
          leftTitle: 'HEAD',
          rightTitle: 'Working tree',
          loader: () async => DiffContent('one\n', 'one\ntwo\n'),
        );
    ctrl.changesDiff = memoryDiff();
    await tester.pumpWidget(MaterialApp(
      theme: buildIdeTheme(Brightness.dark),
      home: Scaffold(body: ChangesView(ctrl: ctrl)),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(DiffView), findsOneWidget);
    expect(find.byTooltip('Close Preview'), findsOneWidget);
    expect(tester.getSize(find.byType(CommitPanel)).width, 380);

    await tester.tap(find.byTooltip('Show Folder Tree'));
    await tester.pump();
    await tester.tap(find.byTooltip('Close Preview'));
    await tester.pump();

    expect(ctrl.changesDiff, isNull);
    expect(find.byType(DiffView), findsNothing);
    expect(tester.getSize(find.byType(CommitPanel)).width, 1200);
    expect(find.byKey(const ValueKey('folder:changes:lib')), findsOneWidget);

    await tester.runAsync(ctrl.refreshStatus);
    await tester.pump();
    expect(ctrl.changesDiff, isNull);
    expect(find.byType(DiffView), findsNothing);

    await tester.tap(find.text('a.dart', findRichText: true));
    expect(ctrl.changesDiff?.change.path, 'lib/a.dart');
    ctrl.changesDiff = memoryDiff();
    await tester.pumpAndSettle();
    expect(find.byType(DiffView), findsOneWidget);
    expect(find.byTooltip('Close Preview'), findsOneWidget);
  });
}
