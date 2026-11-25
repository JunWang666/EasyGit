import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/git_runner.dart';
import 'package:easygit/git/models.dart';
import 'package:easygit/git/progress.dart';
import 'package:easygit/main.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/app_settings.dart';
import 'package:easygit/state/repos_state.dart';
import 'package:easygit/state/task_center.dart';
import 'package:easygit/system/open_requests.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('parses Git object progress, transfer size and speed', () {
    final progress = GitProgress.parse(
      'remote: Receiving objects:  42% (21/50), 1.50 MiB | 2.25 MiB/s',
    );

    expect(progress, isNotNull);
    expect(progress!.phase, 'Receiving objects');
    expect(progress.percent, 42);
    expect(progress.completed, 21);
    expect(progress.total, 50);
    expect(progress.bytes, 1572864);
    expect(progress.bytesPerSecond, 2359296);
  });

  test('parses LFS progress and output split across chunks', () {
    final parser = GitProgressParser();
    final first = parser.feed('Uploading LFS objects:  5');
    final second = parser.feed(
      '0% (1/2), 4.00 MiB | 2.00 MiB/s\r'
      'Writing objects: 100% (2/2), 8 KiB | 4 KiB/s, done.\r',
    );

    expect(first, isEmpty);
    expect(second[0].percent, 50);
    expect(second[0].completed, 1);
    expect(second[0].total, 2);
    expect(second[0].bytes, 4194304);
    expect(second[0].bytesPerSecond, 2097152);
    expect(second[1].phase, 'Writing objects');
    expect(second[1].percent, 100);
  });

  test('task center keeps active tasks when finished tasks are cleared', () {
    final center = TaskCenter();
    final running = center.start('Pushing', subtitle: 'demo');
    final finished = center.start('Fetching', subtitle: 'demo');
    center.succeed(finished);
    final failed = center.start('Cloning demo');
    center.fail(failed, 'Authentication failed');

    expect(center.activeCount, 1);
    expect(finished.status, AppTaskStatus.succeeded);
    expect(failed.error, 'Authentication failed');

    center.clearFinished();
    expect(center.tasks, [running]);
    center.remove(running);
    expect(center.tasks, [running], reason: 'running tasks cannot be removed');
  });

  testWidgets('task center shows live progress without an open repository',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await settings.load();
    final repos = ReposState(settings, AccountsStore());
    await tester.pumpWidget(EasyGitApp(
      settings: settings,
      repos: repos,
      openRequests: OpenRequests(const []),
    ));
    await tester.pump();

    expect(find.text('Tasks'), findsOneWidget);
    final task = repos.tasks.start('Pushing', subtitle: 'demo');
    repos.tasks.update(
      task,
      const GitProgress(
        phase: 'Writing objects',
        percent: 42,
        completed: 21,
        total: 50,
        bytes: 1048576,
        bytesPerSecond: 2097152,
      ),
    );
    await tester.pump();

    expect(find.text('Pushing 42% · 2.00 MiB/s'), findsOneWidget);
    await tester.tap(find.byTooltip('Task center'));
    await tester.pump();

    expect(find.text('Writing objects 42% (21/50)'), findsOneWidget);
    expect(find.text('1.00 MiB'), findsOneWidget);
    expect(find.text('2.00 MiB/s'), findsOneWidget);

    repos.tasks.succeed(task);
    await tester.pump();
    expect(find.textContaining('Completed'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear finished tasks'));
    await tester.pump();
    expect(find.text('No background tasks'), findsOneWidget);
  });

  test('real clone and push emit native Git progress and speed', () async {
    final tmp = await Directory.systemTemp.createTemp('easygit_tasks');
    addTearDown(() => tmp.delete(recursive: true).catchError((_) => tmp));
    final source = '${tmp.path}/source'.replaceAll('\\', '/');
    await Directory(source).create();

    Future<void> git(String dir, List<String> args) async {
      final result = await Process.run('git', args, workingDirectory: dir);
      if (result.exitCode != 0) {
        throw StateError('git ${args.join(' ')}: ${result.stderr}');
      }
    }

    await git(source, ['init', '-b', 'main']);
    await git(source, ['config', 'user.email', 'tasks@example.com']);
    await git(source, ['config', 'user.name', 'Task Test']);
    await File('$source/data.bin').writeAsBytes(
      List<int>.generate(2 * 1024 * 1024, (index) => index % 251),
    );
    await git(source, ['add', '.']);
    await git(source, ['commit', '-m', 'source']);

    final center = TaskCenter();
    final cloneTask = center.start('Cloning source');
    final cloneParser = GitProgressParser();
    final cloneProgress = <GitProgress>[];
    await GitRepository.clone(Uri.file(source).toString(), tmp.path, 'clone',
        onProgress: (chunk) {
      for (final progress in cloneParser.feed(chunk)) {
        cloneProgress.add(progress);
        center.update(cloneTask, progress);
      }
    });
    center.succeed(cloneTask);

    expect(
      cloneProgress.any((progress) => progress.phase == 'Receiving objects'),
      isTrue,
    );

    final cloned = '${tmp.path}/clone'.replaceAll('\\', '/');
    final bare = '${tmp.path}/bare.git'.replaceAll('\\', '/');
    await git(tmp.path, ['init', '--bare', bare]);
    await git(cloned, ['remote', 'set-url', 'origin', bare]);
    await git(cloned, ['config', 'user.email', 'tasks@example.com']);
    await git(cloned, ['config', 'user.name', 'Task Test']);
    await File('$cloned/data.bin').writeAsBytes(
      List<int>.generate(3 * 1024 * 1024, (index) => index % 239),
    );
    await git(cloned, ['add', '.']);
    await git(cloned, ['commit', '-m', 'push']);

    final repo = await GitRepository.open(cloned);
    final pushTask = center.start('Pushing');
    final pushParser = GitProgressParser();
    final pushProgress = <GitProgress>[];
    await repo.push(onProgress: (chunk) {
      for (final progress in pushParser.feed(chunk)) {
        pushProgress.add(progress);
        center.update(pushTask, progress);
      }
    });
    center.succeed(pushTask);

    expect(
      pushProgress.any((progress) => progress.phase == 'Writing objects'),
      isTrue,
    );
    expect(
      pushProgress.any((progress) => progress.bytesPerSecond != null),
      isTrue,
    );
    expect(center.activeCount, 0);
  });

  test('cancel invokes the task callback and marks the task cancelled', () {
    final center = TaskCenter();
    final task = center.start('Fetching');
    var calls = 0;
    task.onCancel = () => calls++;

    center.cancel(task);
    expect(calls, 1);
    expect(task.cancellable, isTrue);

    center.cancelled(task);
    expect(task.status, AppTaskStatus.cancelled);
    expect(task.cancellable, isFalse);

    center.cancel(task);
    expect(calls, 1);
  });

  test('cancelling a runner kills its git process and resets afterwards',
      () async {
    if (Platform.isWindows) return;
    final tmp = await Directory.systemTemp.createTemp('easygit_cancel');
    addTearDown(() => tmp.delete(recursive: true));
    await _installFakeGit(tmp);

    final runner = GitRunner(tmp.path);
    final running = runner.run(['status']);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    runner.cancel();

    await expectLater(
      running,
      throwsA(isA<GitException>()
          .having((e) => e.isCancelled, 'isCancelled', isTrue)),
    );

    GitRunner.executable = 'git';
    final out = await runner.run(['--version']);
    expect(out, contains('git version'));
  });

  test('cancel requested while the process is spawning still stops it',
      () async {
    if (Platform.isWindows) return;
    final tmp = await Directory.systemTemp.createTemp('easygit_cancel');
    addTearDown(() => tmp.delete(recursive: true));
    await _installFakeGit(tmp);

    final runner = GitRunner(tmp.path);
    final running = runner.run(['status']);
    runner.cancel();

    await expectLater(
      running,
      throwsA(isA<GitException>()
          .having((e) => e.isCancelled, 'isCancelled', isTrue)),
    );
  });
}

Future<void> _installFakeGit(Directory tmp) async {
  final fake = File('${tmp.path}/fakegit');
  await fake.writeAsString('#!/bin/sh\nsleep 30\n');
  await Process.run('chmod', ['+x', fake.path]);
  final previous = GitRunner.executable;
  addTearDown(() => GitRunner.executable = previous);
  GitRunner.executable = fake.path;
}
