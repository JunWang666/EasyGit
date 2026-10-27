import 'dart:io';

import 'package:flutter/material.dart';

import '../../git/lfs.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';

const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

/// Diff of a Git LFS file: sizes, object ids and image previews.
class LfsDiffCard extends StatelessWidget {
  const LfsDiffCard({
    super.key,
    required this.diff,
    required this.path,
    required this.leftTitle,
    required this.rightTitle,
    required this.onChanged,
  });

  final LfsDiff diff;
  final String path;
  final String leftTitle;
  final String rightTitle;

  /// Called after a download so the card reloads.
  final VoidCallback onChanged;

  bool get _isImage {
    final dot = path.lastIndexOf('.');
    return dot >= 0 && _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final left = diff.left;
    final right = diff.right;
    String change;
    if (left == null && right != null) {
      change = 'Added · ${formatBytes(right.size)}';
    } else if (left != null && right == null) {
      change = 'Deleted · was ${formatBytes(left.size)}';
    } else if (left != null && right != null) {
      final delta = right.size - left.size;
      change = '${formatBytes(left.size)} → ${formatBytes(right.size)}'
          '${delta == 0 ? '' : ' (${delta > 0 ? '+' : '−'}${formatBytes(delta.abs())})'}';
    } else {
      change = '';
    }

    return Container(
      color: c.editorBg,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: c.accent.withAlpha(40),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('Git LFS',
                style: TextStyle(fontSize: 11.5, color: c.accent, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Text(change, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Text('Large file stored outside the repository. Git only keeps a small pointer to it.',
            style: TextStyle(fontSize: 12, color: c.textSecondary)),
        const SizedBox(height: 14),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _side(context, leftTitle, left)),
            const SizedBox(width: 12),
            Expanded(child: _side(context, rightTitle, right)),
          ]),
        ),
      ]),
    );
  }

  Widget _side(BuildContext context, String title, LfsSide? side) {
    final c = IdeColors.of(context);
    Widget body;
    if (side == null) {
      body = Center(child: Text('(no file)', style: TextStyle(color: c.textDisabled)));
    } else if (!side.available) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_download_outlined, size: 30, color: c.textSecondary),
          const SizedBox(height: 8),
          Text('Not downloaded', style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 10),
          if (side.download != null)
            IdeButton(
              label: 'Download ${formatBytes(side.size)}',
              onPressed: () async {
                await side.download!();
                onChanged();
              },
            ),
        ]),
      );
    } else if (_isImage && side.size < 40 * 1024 * 1024) {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Image.file(
          File(side.localPath!),
          fit: BoxFit.contain,
          errorBuilder: (context, _, __) =>
              Center(child: Text('Cannot preview', style: TextStyle(color: c.textSecondary))),
        ),
      );
    } else {
      body = Center(
        child: Icon(Icons.insert_drive_file_outlined, size: 36, color: c.textDisabled),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: c.panelBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (side != null) Text(formatBytes(side.size), style: TextStyle(color: c.textSecondary)),
          ]),
        ),
        Expanded(child: body),
        if (side?.pointer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: SelectableText('oid ${side!.pointer!.oid.substring(0, 16)}…',
                style: monoStyle(context, size: 11.5, color: c.textSecondary)),
          ),
      ]),
    );
  }
}
