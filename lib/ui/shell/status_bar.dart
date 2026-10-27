import 'package:flutter/material.dart';

import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.ctrl,
    required this.onBranchTap,
    required this.consoleVisible,
    required this.onToggleConsole,
  });

  final RepoController ctrl;
  final VoidCallback onBranchTap;
  final bool consoleVisible;
  final VoidCallback onToggleConsole;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final small = TextStyle(fontSize: 12, color: c.textSecondary);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final status = ctrl.status;
        return Container(
          height: 26,
          color: c.panelBg,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Icon(Icons.folder_outlined, size: 13, color: c.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(ctrl.repo.root,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
            ),
            if (ctrl.busy != null) ...[
              const SizedBox(width: 16),
              const SizedBox(
                  width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5)),
              const SizedBox(width: 6),
              Text('${ctrl.busy}...', style: small),
            ],
            const Spacer(),
            if (status != null) ...[
              Text(
                  '${status.changes.length} change${status.changes.length == 1 ? '' : 's'}',
                  style: small),
              const SizedBox(width: 12),
              HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: onBranchTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: hovered ? c.hover : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      Icon(Icons.call_split, size: 13, color: c.textSecondary),
                      const SizedBox(width: 4),
                      Text(status.headLabel, style: small),
                      if (status.behind > 0)
                        Text('  ↓${status.behind}', style: small.copyWith(color: c.accent)),
                      if (status.ahead > 0)
                        Text('  ↑${status.ahead}', style: small.copyWith(color: c.success)),
                    ]),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            HoverBuilder(
              cursor: SystemMouseCursors.click,
              builder: (context, hovered) => GestureDetector(
                onTap: onToggleConsole,
                child: Tooltip(
                  message: 'Git console (${shortcutLabel('`')})',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: consoleVisible ? c.selectionInactive : (hovered ? c.hover : null),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      Icon(Icons.terminal, size: 13, color: c.textSecondary),
                      const SizedBox(width: 4),
                      Text('Console', style: small),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
