import 'package:flutter/material.dart';

import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';

/// The "Console" tab: git commands run on the user's behalf and their output.
class ConsolePanel extends StatelessWidget {
  const ConsolePanel({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final logs = ctrl.consoleLog;
        if (logs.isEmpty) return const EmptyHint('Git commands will be shown here');
        return Container(
          color: c.editorBg,
          child: SelectionArea(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(10),
              itemCount: logs.length,
              itemBuilder: (context, i) {
                final log = logs[logs.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${formatTime(log.time)}  ',
                          style: monoStyle(context, size: 12, color: c.textSecondary)),
                      TextSpan(
                          text: log.command,
                          style: monoStyle(context, size: 12, color: c.accent)),
                    ])),
                    if (log.output.isNotEmpty)
                      Text(log.output,
                          style: monoStyle(context,
                              size: 12, color: log.failed ? c.error : c.text)),
                  ]),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
