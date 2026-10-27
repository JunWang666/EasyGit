import 'dart:io';

import 'package:flutter/material.dart';

import '../../git/lfs.dart';
import '../../git/models.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

/// Files at least this large get the "store with LFS?" question.
const largeFileBytes = 50 * 1024 * 1024;

enum _LargeFileChoice { track, commitAnyway }

/// Commits the selected files, first offering Git LFS for large ones.
Future<void> commitFlow(BuildContext context, RepoController ctrl, {bool andPush = false}) async {
  final selected =
      ctrl.status?.changes.where((c) => ctrl.included.contains(c.path)).toList() ?? const [];
  // Let commit() report a missing message or empty selection first.
  if (ctrl.messageController.text.trim().isEmpty || selected.isEmpty) {
    await ctrl.commit(andPush: andPush);
    return;
  }
  final large = <(FileChange, int)>[];
  for (final f in selected) {
    if (f.kind == ChangeKind.deleted || ctrl.lfs.isTracked(f.path)) continue;
    final file = File('${ctrl.repo.root}/${f.path}');
    if (!await file.exists()) continue;
    final size = await file.length();
    if (size >= largeFileBytes) large.add((f, size));
  }
  if (large.isEmpty) {
    await ctrl.commit(andPush: andPush);
    return;
  }
  if (!context.mounted) return;

  final patterns = {for (final (f, _) in large) _patternFor(f.path)}.toList();
  final choice = await showDialog<_LargeFileChoice>(
    context: context,
    builder: (context) => _LargeFilesDialog(
      files: large,
      patterns: patterns,
      lfsInstalled: ctrl.lfs.installed,
    ),
  );
  switch (choice) {
    case null:
      return;
    case _LargeFileChoice.commitAnyway:
      await ctrl.commit(andPush: andPush);
    case _LargeFileChoice.track:
      if (!await ctrl.lfsTrack(patterns)) return;
      // Make sure LFS hooks exist so the push uploads the files.
      if (!await ctrl.repo.lfsHooksInstalled()) await ctrl.repo.lfsInstallHooks();
      await ctrl.refreshStatus();
      ctrl.toggleIncluded('.gitattributes', true);
      await ctrl.commit(andPush: andPush);
  }
}

/// `*.psd` for files with an extension, else the exact path.
String _patternFor(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) return '*.${name.substring(dot + 1).toLowerCase()}';
  return path;
}

class _LargeFilesDialog extends StatelessWidget {
  const _LargeFilesDialog({required this.files, required this.patterns, required this.lfsInstalled});

  final List<(FileChange, int)> files;
  final List<String> patterns;
  final bool lfsInstalled;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final over100 = files.any((f) => f.$2 > 100 * 1024 * 1024);
    return IdeDialog(
      title: 'Large Files',
      width: 560,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'These files are large. Stored in Git, every version stays in the history forever '
            'and slows down cloning.${over100 ? ' GitHub rejects files over 100 MB.' : ''}',
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: c.editorBg,
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(5),
            ),
            child: ListView(shrinkWrap: true, children: [
              for (final (f, size) in files)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Row(children: [
                    Expanded(child: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(formatBytes(size),
                        style: TextStyle(
                            color: size > 100 * 1024 * 1024 ? c.error : c.textSecondary)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (lfsInstalled)
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Recommended: store '),
              TextSpan(
                  text: patterns.join(', '), style: const TextStyle(fontWeight: FontWeight.w600)),
              const TextSpan(
                  text: ' with Git LFS. EasyGit updates .gitattributes and commits it together '
                      'with these files.'),
            ]))
          else
            Text('Git LFS is not installed, so EasyGit cannot store them with LFS.',
                style: TextStyle(color: c.warning)),
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(
          label: 'Commit Anyway',
          onPressed: () => Navigator.pop(context, _LargeFileChoice.commitAnyway),
        ),
        if (lfsInstalled)
          IdeButton(
            label: 'Use LFS and Commit',
            primary: true,
            onPressed: () => Navigator.pop(context, _LargeFileChoice.track),
          ),
      ],
    );
  }
}
