import 'package:flutter/material.dart';

import '../../state/repo_controller.dart';
import '../../state/task_center.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.ctrl,
    required this.tasks,
    required this.onBranchTap,
    required this.consoleVisible,
    required this.onToggleConsole,
    required this.tasksVisible,
    required this.onToggleTasks,
  });

  final RepoController? ctrl;
  final TaskCenter tasks;
  final VoidCallback onBranchTap;
  final bool consoleVisible;
  final VoidCallback onToggleConsole;
  final bool tasksVisible;
  final VoidCallback onToggleTasks;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final small = TextStyle(fontSize: 12, color: c.textSecondary);
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl, tasks]),
      builder: (context, _) {
        final status = ctrl?.status;
        return Container(
          height: 26,
          color: c.panelBg,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            Icon(Icons.folder_outlined, size: 13, color: c.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(ctrl?.repo.root ?? 'EasyGit',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
            ),
            _TasksButton(
              tasks: tasks,
              visible: tasksVisible,
              onTap: onToggleTasks,
            ),
            if (status != null) ...[
              const SizedBox(width: 8),
              HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: onBranchTap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: hovered ? c.hover : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      Icon(Icons.call_split, size: 13, color: c.textSecondary),
                      const SizedBox(width: 4),
                      Text(status.headLabel, style: small),
                      if (status.behind > 0)
                        Text('  ↓${status.behind}',
                            style: small.copyWith(color: c.accent)),
                      if (status.ahead > 0)
                        Text('  ↑${status.ahead}',
                            style: small.copyWith(color: c.success)),
                    ]),
                  ),
                ),
              ),
            ],
            if (ctrl != null) ...[
              const SizedBox(width: 8),
              HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  onTap: onToggleConsole,
                  child: Tooltip(
                    message: 'Git console (${shortcutLabel('`')})',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: consoleVisible
                            ? c.selectionInactive
                            : (hovered ? c.hover : null),
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
            ],
          ]),
        );
      },
    );
  }
}

class _TasksButton extends StatelessWidget {
  const _TasksButton({
    required this.tasks,
    required this.visible,
    required this.onTap,
  });

  final TaskCenter tasks;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final task = tasks.active.firstOrNull;
    final progress = task?.progress;
    final small = TextStyle(fontSize: 12, color: c.textSecondary);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: 'Task center',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: visible ? c.selectionInactive : (hovered ? c.hover : null),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(task == null ? Icons.task_alt : Icons.sync,
                  size: 13, color: c.textSecondary),
              const SizedBox(width: 5),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 64,
                    height: 3,
                    child: LinearProgressIndicator(
                      value: progress.fraction,
                      backgroundColor: c.hover,
                      color: c.accent,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  task == null ? 'Tasks' : _taskLabel(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small,
                ),
              ),
              if (tasks.activeCount > 1)
                Text(' +${tasks.activeCount - 1}', style: small),
            ]),
          ),
        ),
      ),
    );
  }

  String _taskLabel(AppTask task) {
    final progress = task.progress;
    if (progress == null) return '${task.title}...';
    final percent = progress.percent == null ? '' : ' ${progress.percent}%';
    final speed = progress.bytesPerSecond == null
        ? ''
        : ' · ${formatSpeed(progress.bytesPerSecond!)}';
    return '${task.title}$percent$speed';
  }
}
