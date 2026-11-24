import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../git/progress.dart';
import '../../state/repos_state.dart';
import 'clone_dialog.dart';
import '../widgets/dialogs.dart';

/// Adds the repository at [path] to the sidebar, offering `git init` when the
/// folder is not a repository yet.
Future<void> openRepositoryAt(
    BuildContext context, ReposState repos, String path,
    {String? accountId}) async {
  try {
    final ctrl = await repos.open(path);
    if (accountId != null) await ctrl.setAccount(accountId);
  } on GitException catch (e) {
    if (!context.mounted) return;
    if (!e.message.contains('not a git repository')) {
      await showConfirmDialog(context,
          title: 'Cannot Open Repository', message: e.message);
      return;
    }
    final init = await showConfirmDialog(context,
        title: 'Not a Git Repository',
        message:
            '$path is not a Git repository.\n\nCreate a new repository there?',
        okLabel: 'Create Repository');
    if (!init || !context.mounted) return;
    try {
      await GitRepository.init(path);
      await repos.open(path);
    } on GitException catch (e2) {
      if (context.mounted) {
        await showConfirmDialog(context,
            title: 'Cannot Create Repository', message: e2.message);
      }
    }
  }
}

/// Opens a folder chosen outside the app (command line, Explorer context
/// menu). The repository may be the folder itself, a parent (found by git),
/// or folders below it, in which case the user picks one or all of them.
Future<void> openFolderFlow(
    BuildContext context, ReposState repos, String path) async {
  try {
    await repos.open(path);
    return;
  } on GitException catch (e) {
    if (!e.message.contains('not a git repository')) {
      if (context.mounted) {
        await showConfirmDialog(context,
            title: 'Cannot Open Repository', message: e.message);
      }
      return;
    }
  }
  final found = await findRepositoriesBelow(path);
  if (!context.mounted) return;
  if (found.isEmpty) {
    await openRepositoryAt(context, repos, path); // offers git init
    return;
  }
  if (found.length == 1) {
    await openRepositoryAt(context, repos, found.single);
    return;
  }
  const all = '';
  final choice = await showChoiceDialog<String>(
    context,
    title: 'Open Repository',
    message: '$path is not a Git repository, but these folders inside it are:',
    options: [
      for (final r in found) ChoiceOption(r, _relative(r, path), r),
      ChoiceOption(all, 'All ${found.length} repositories',
          'Adds each one to the sidebar.'),
    ],
    initial: found.first,
    okLabel: 'Open',
  );
  if (choice == null || !context.mounted) return;
  for (final r in choice == all ? found : [choice]) {
    if (!context.mounted) return;
    await openRepositoryAt(context, repos, r);
  }
}

String _relative(String path, String base) {
  final p = path.replaceAll('\\', '/');
  final b = base.replaceAll('\\', '/').replaceFirst(RegExp(r'/$'), '');
  return p.startsWith('$b/') ? p.substring(b.length + 1) : p;
}

/// Working trees in folders below [dir], up to [depth] levels down. Folders
/// that are repositories are not searched further.
Future<List<String>> findRepositoriesBelow(String dir,
    {int depth = 2, int limit = 50}) async {
  const skip = {
    'node_modules',
    'build',
    'dist',
    'target',
    'vendor',
    r'$RECYCLE.BIN'
  };
  final found = <String>[];
  var level = [Directory(dir)];
  for (var d = 0; d < depth && level.isNotEmpty && found.length < limit; d++) {
    final next = <Directory>[];
    for (final parent in level) {
      try {
        await for (final e in parent.list(followLinks: false)) {
          if (e is! Directory) continue;
          final name = e.path.split(RegExp(r'[\\/]')).last;
          if (name.startsWith('.') || skip.contains(name)) continue;
          if (await FileSystemEntity.type('${e.path}/.git') !=
              FileSystemEntityType.notFound) {
            found.add(e.path);
            if (found.length >= limit) break;
          } else {
            next.add(e);
          }
        }
      } on FileSystemException {
        // Unreadable folder: skip it.
      }
      if (found.length >= limit) break;
    }
    level = next;
  }
  found.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return found;
}

Future<void> openRepositoryFlow(BuildContext context, ReposState repos) async {
  final path =
      await FilePicker.getDirectoryPath(dialogTitle: 'Open Git Repository');
  if (path != null && context.mounted)
    await openRepositoryAt(context, repos, path);
}

Future<void> cloneRepositoryFlow(BuildContext context, ReposState repos,
    {String? initialUrl, String? initialAccountId}) async {
  final request = await showCloneDialog(context, repos.accounts,
      initialUrl: initialUrl, initialAccountId: initialAccountId);
  if (request == null || !context.mounted) return;
  final account = repos.accounts.accounts
      .where((a) => a.id == request.accountId)
      .firstOrNull;
  final task =
      repos.tasks.start('Cloning ${request.folder}', subtitle: request.url);
  final parser = GitProgressParser();
  GitException? error;
  try {
    await GitRepository.clone(
      request.url,
      request.parent,
      request.folder,
      credentials: account == null
          ? null
          : repos.accounts.credentialsPreferring(account),
      onProgress: (chunk) {
        for (final progress in parser.feed(chunk)) {
          repos.tasks.update(task, progress);
        }
      },
    );
    repos.tasks.succeed(task);
  } on GitException catch (e) {
    error = e;
    repos.tasks.fail(task, e.message);
  } catch (e) {
    repos.tasks.fail(task, '$e');
    rethrow;
  }
  if (!context.mounted) return;
  if (error != null) {
    await showConfirmDialog(context,
        title: 'Clone Failed', message: error.message);
    return;
  }
  await openRepositoryAt(context, repos, '${request.parent}/${request.folder}',
      accountId: account?.id);
}
