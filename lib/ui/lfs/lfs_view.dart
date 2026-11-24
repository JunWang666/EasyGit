import 'package:flutter/material.dart';

import '../../git/lfs.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';
import 'lfs_dialog.dart';

/// Git LFS files arranged like a file browser, with folder-level transfer actions.
class LfsView extends StatefulWidget {
  const LfsView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  State<LfsView> createState() => _LfsViewState();
}

class _LfsViewState extends State<LfsView> {
  final Set<String> _expanded = {''};

  RepoController get ctrl => widget.ctrl;

  Future<void> _clearLocal(LfsTreeNode node) async {
    final files =
        node.files.where((f) => f.downloaded || f.checkedOut).toList();
    if (files.isEmpty) return;
    final target = node.path.isEmpty ? 'all LFS files' : '"${node.path}"';
    final ok = await showConfirmDialog(context,
        title: 'Clear Local LFS Data',
        message:
            'Clear downloaded content and cached objects for ${files.length} '
            'file${files.length == 1 ? '' : 's'} in $target?\n\n'
            'Working-tree files become small Git LFS pointers. Files with local changes and '
            'objects needed by unpushed commits are left untouched. Nothing is deleted from '
            'Git or the server.',
        okLabel: 'Clear Local Data');
    if (ok) await ctrl.lfsClearLocal(files);
  }

  void _contextMenu(Offset position, LfsTreeNode node) {
    final files = node.files;
    final missing = files.any((f) => !f.checkedOut);
    final uploadable = files.any((f) => f.downloaded && f.oid.isNotEmpty);
    final local = files.any((f) => f.downloaded || f.checkedOut);
    showIdeMenu(context, position, [
      if (missing)
        IdeMenuItem('Download ${node.isFolder ? 'Folder' : 'File'}',
            icon: Icons.download_outlined,
            enabled: ctrl.busy == null,
            onTap: () => ctrl.lfsDownload([for (final f in files) f.path])),
      if (uploadable && ctrl.primaryRemote != null)
        IdeMenuItem('Upload ${node.isFolder ? 'Folder' : 'File'}',
            icon: Icons.cloud_upload_outlined,
            enabled: ctrl.busy == null,
            onTap: () => ctrl.lfsUpload(files)),
      if (local)
        IdeMenuItem('Clear Local Data...',
            icon: Icons.cleaning_services_outlined,
            enabled: ctrl.busy == null,
            onTap: () => _clearLocal(node)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final lfs = ctrl.lfs;
        final root = buildLfsTree(lfs.files.values);
        final missing = lfs.missing;
        return Container(
          color: c.editorBg,
          child: Column(children: [
            Container(
              height: 46,
              color: c.panelBg,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Icon(Icons.cloud_outlined, size: 18, color: c.icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${root.fileCount} file${root.fileCount == 1 ? '' : 's'} · '
                    '${formatBytes(root.totalSize)}'
                    '${missing.isEmpty ? '' : ' · ${missing.length} not downloaded'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
                if (missing.isNotEmpty && lfs.installed) ...[
                  IdeButton(
                    label: 'Download All',
                    primary: true,
                    onPressed:
                        ctrl.busy == null ? () => ctrl.lfsDownload() : null,
                  ),
                  const SizedBox(width: 6),
                ],
                IdeIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Refresh',
                  onPressed: ctrl.busy == null ? ctrl.refreshAll : null,
                ),
                const SizedBox(width: 4),
                IdeButton(
                  label: 'LFS Settings...',
                  onPressed: () => showLfsDialog(context, ctrl),
                ),
              ]),
            ),
            Container(height: 1, color: c.splitter),
            if (ctrl.transferProgress case final progress?)
              Container(
                height: 28,
                color: c.panelBg,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      minHeight: 5,
                      backgroundColor: c.hover,
                      color: c.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${progress.uploading ? 'Uploading' : 'Downloading'} '
                    '${progress.percent}% · '
                    '${progress.completedFiles}/${progress.totalFiles} files',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ]),
              ),
            if (!lfs.installed)
              const Expanded(
                child: EmptyHint(
                    'Install Git LFS to browse and download large files.'),
              )
            else if (!lfs.usesLfs)
              const Expanded(
                child: EmptyHint('This repository does not use Git LFS yet. '
                    'Open LFS Settings to track a file pattern.'),
              )
            else if (root.fileCount == 0)
              const Expanded(
                  child: EmptyHint('No LFS files in the current revision.'))
            else ...[
              _header(),
              Container(height: 1, color: c.border),
              Expanded(child: ListView(children: _rows(root, 0))),
            ],
          ]),
        );
      },
    );
  }

  Widget _header() {
    final c = IdeColors.of(context);
    final style = TextStyle(
        fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600);
    return Container(
      height: 28,
      color: c.panelBg,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(child: Text('Name', style: style)),
        SizedBox(
            width: 90,
            child: Text('Size', textAlign: TextAlign.right, style: style)),
        const SizedBox(width: 12),
        SizedBox(width: 150, child: Text('Local status', style: style)),
        const SizedBox(width: 88),
      ]),
    );
  }

  List<Widget> _rows(LfsTreeNode node, int depth) => [
        _row(node, depth),
        if (node.isFolder && _expanded.contains(node.path))
          for (final child in node.children) ..._rows(child, depth + 1),
      ];

  Widget _row(LfsTreeNode node, int depth) {
    final c = IdeColors.of(context);
    final files = node.files;
    final name = node.path.isEmpty ? ctrl.name : node.name;
    final missing = files.where((f) => !f.checkedOut).length;
    final local = files.where((f) => f.downloaded || f.checkedOut).length;
    final status = node.isFolder
        ? (missing == 0 ? 'All downloaded' : '$missing not downloaded')
        : node.file!.checkedOut
            ? 'Downloaded'
            : node.file!.downloaded
                ? 'Cached · pointer only'
                : 'Not downloaded';
    return ListRow(
      key: ValueKey('lfs-tree-${node.path}'),
      height: 34,
      indent: depth * 18,
      onTap: node.isFolder
          ? () => setState(() {
                if (!_expanded.remove(node.path)) _expanded.add(node.path);
              })
          : null,
      onContextMenu: (position) => _contextMenu(position, node),
      child: Row(children: [
        SizedBox(
          width: 16,
          child: node.isFolder
              ? Icon(
                  _expanded.contains(node.path)
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 16,
                  color: c.textSecondary,
                )
              : null,
        ),
        Icon(
          node.isFolder
              ? (_expanded.contains(node.path)
                  ? Icons.folder_open_outlined
                  : Icons.folder_outlined)
              : fileIcon(node.name),
          size: 16,
          color: node.isFolder ? c.accent : c.icon,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        SizedBox(
          width: 90,
          child: Text(
            formatBytes(node.totalSize),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 150,
          child: Text(
            node.isFolder && local > 0 && missing > 0
                ? '$status · $local cached'
                : status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: missing > 0 ? c.accent : c.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 88,
          child: Row(children: [
            if (missing > 0)
              IdeIconButton(
                icon: Icons.download_outlined,
                tooltip: 'Download $name',
                size: 28,
                iconSize: 15,
                onPressed: ctrl.busy == null
                    ? () => ctrl.lfsDownload([for (final f in files) f.path])
                    : null,
              )
            else
              const SizedBox(width: 28),
            if (files.any((f) => f.downloaded && f.oid.isNotEmpty) &&
                ctrl.primaryRemote != null)
              IdeIconButton(
                icon: Icons.cloud_upload_outlined,
                tooltip: 'Upload $name',
                size: 28,
                iconSize: 15,
                onPressed:
                    ctrl.busy == null ? () => ctrl.lfsUpload(files) : null,
              )
            else
              const SizedBox(width: 28),
            if (local > 0)
              IdeIconButton(
                icon: Icons.cleaning_services_outlined,
                tooltip: 'Clear local data: $name',
                size: 28,
                iconSize: 15,
                onPressed: ctrl.busy == null ? () => _clearLocal(node) : null,
              ),
          ]),
        ),
      ]),
    );
  }
}
