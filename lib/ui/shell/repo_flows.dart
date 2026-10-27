import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../git/git_repository.dart';
import '../../git/models.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import 'clone_dialog.dart';
import '../widgets/dialogs.dart';

/// Adds the repository at [path] to the sidebar, offering `git init` when the
/// folder is not a repository yet.
Future<void> openRepositoryAt(BuildContext context, ReposState repos, String path) async {
  try {
    await repos.open(path);
  } on GitException catch (e) {
    if (!context.mounted) return;
    if (!e.message.contains('not a git repository')) {
      await showConfirmDialog(context, title: 'Cannot Open Repository', message: e.message);
      return;
    }
    final init = await showConfirmDialog(context,
        title: 'Not a Git Repository',
        message: '$path is not a Git repository.\n\nCreate a new repository there?',
        okLabel: 'Create Repository');
    if (!init || !context.mounted) return;
    try {
      await GitRepository.init(path);
      await repos.open(path);
    } on GitException catch (e2) {
      if (context.mounted) {
        await showConfirmDialog(context, title: 'Cannot Create Repository', message: e2.message);
      }
    }
  }
}

Future<void> openRepositoryFlow(BuildContext context, ReposState repos) async {
  final path = await FilePicker.getDirectoryPath(dialogTitle: 'Open Git Repository');
  if (path != null && context.mounted) await openRepositoryAt(context, repos, path);
}

Future<void> cloneRepositoryFlow(BuildContext context, ReposState repos,
    {String? initialUrl}) async {
  final request = await showCloneDialog(context, repos.accounts, initialUrl: initialUrl);
  if (request == null || !context.mounted) return;
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _Progress('Cloning ${request.url}...'),
  );
  GitException? error;
  try {
    await GitRepository.clone(request.url, request.parent, request.folder);
  } on GitException catch (e) {
    error = e;
  } finally {
    navigator.pop();
  }
  if (!context.mounted) return;
  if (error != null) {
    await showConfirmDialog(context, title: 'Clone Failed', message: error.message);
    return;
  }
  await openRepositoryAt(context, repos, '${request.parent}/${request.folder}');
}

class _Progress extends StatelessWidget {
  const _Progress(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return Dialog(
      backgroundColor: c.popupBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 14),
          Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }
}
