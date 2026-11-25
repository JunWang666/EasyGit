import 'package:flutter/material.dart';

import '../../state/task_center.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';

class TaskCenterPanel extends StatelessWidget {
  const TaskCenterPanel({
    super.key,
    required this.tasks,
    required this.onClose,
  });

  final TaskCenter tasks;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: tasks,
      builder: (context, _) => Container(
        width: 440,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: c.popupBg,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 16),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            height: 40,
            child: Row(children: [
              const SizedBox(width: 12),
              const Text('Tasks',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              if (tasks.activeCount > 0) ...[
                const SizedBox(width: 8),
                Text('${tasks.activeCount} running',
                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ],
              const Spacer(),
              IdeIconButton(
                icon: Icons.delete_sweep_outlined,
                tooltip: 'Clear finished tasks',
                onPressed: tasks.tasks.any((task) => !task.running)
                    ? tasks.clearFinished
                    : null,
              ),
              IdeIconButton(
                  icon: Icons.close, tooltip: 'Close', onPressed: onClose),
              const SizedBox(width: 4),
            ]),
          ),
          Container(height: 1, color: c.splitter),
          Flexible(
            child: tasks.tasks.isEmpty
                ? const SizedBox(
                    height: 110,
                    child: Center(child: Text('No background tasks')),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: tasks.tasks.length,
                    separatorBuilder: (_, __) =>
                        Container(height: 1, color: c.splitter),
                    itemBuilder: (context, index) =>
                        _TaskRow(task: tasks.tasks[index], tasks: tasks),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.tasks});

  final AppTask task;
  final TaskCenter tasks;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final progress = task.progress;
    final secondary = TextStyle(fontSize: 11.5, color: c.textSecondary);
    final elapsed = task.finishedAt?.difference(task.startedAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 20,
          height: 20,
          child: switch (task.status) {
            AppTaskStatus.running =>
              const CircularProgressIndicator(strokeWidth: 1.8),
            AppTaskStatus.succeeded =>
              Icon(Icons.check_circle_outline, size: 18, color: c.success),
            AppTaskStatus.failed =>
              Icon(Icons.error_outline, size: 18, color: c.error),
            AppTaskStatus.cancelled =>
              Icon(Icons.cancel_outlined, size: 18, color: c.textSecondary),
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5)),
            if (task.subtitle != null) ...[
              const SizedBox(height: 2),
              Text(task.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary),
            ],
            const SizedBox(height: 5),
            if (task.running) ...[
              Row(children: [
                Expanded(
                  child: Text(
                    _progressLabel(task),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondary,
                  ),
                ),
                if (progress?.bytes != null) ...[
                  const SizedBox(width: 8),
                  Text(formatBytes(progress!.bytes!), style: secondary),
                ],
                if (progress?.bytesPerSecond != null) ...[
                  const SizedBox(width: 8),
                  Text(formatSpeed(progress!.bytesPerSecond!),
                      style: secondary),
                ],
              ]),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress?.fraction,
                minHeight: 4,
                backgroundColor: c.hover,
                color: c.accent,
              ),
            ] else
              Text(
                task.status == AppTaskStatus.failed
                    ? (task.error ?? 'Failed')
                    : task.status == AppTaskStatus.cancelled
                        ? 'Cancelled'
                        : 'Completed${_elapsed(elapsed)}',
                maxLines: task.status == AppTaskStatus.failed ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                style: secondary.copyWith(
                    color: task.status == AppTaskStatus.failed
                        ? c.error
                        : c.textSecondary),
              ),
          ]),
        ),
        if (task.cancellable)
          IdeIconButton(
            icon: Icons.close,
            tooltip: 'Cancel task',
            size: 22,
            iconSize: 14,
            onPressed: () => tasks.cancel(task),
          ),
        if (!task.running)
          IdeIconButton(
            icon: Icons.close,
            tooltip: 'Remove task',
            size: 22,
            iconSize: 14,
            onPressed: () => tasks.remove(task),
          ),
      ]),
    );
  }

  String _progressLabel(AppTask task) {
    final progress = task.progress;
    if (progress == null) return 'Working...';
    final counts = progress.completed != null && progress.total != null
        ? ' (${progress.completed}/${progress.total})'
        : '';
    final percent = progress.percent == null ? '' : ' ${progress.percent}%';
    return '${progress.phase}$percent$counts';
  }

  String _elapsed(Duration? elapsed) {
    if (elapsed == null) return '';
    if (elapsed.inSeconds < 1) return ' in less than a second';
    if (elapsed.inMinutes < 1) return ' in ${elapsed.inSeconds} s';
    return ' in ${elapsed.inMinutes} min ${elapsed.inSeconds % 60} s';
  }
}
