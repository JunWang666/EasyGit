
import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/app_settings.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../accounts/accounts_dialog.dart';
import '../settings/network_dialog.dart';
import '../widgets/menus.dart';
import 'window_chrome.dart';

/// Top bar: repository and branch widgets, then labelled Git actions.
class MainToolbar extends StatelessWidget {
  const MainToolbar({
    super.key,
    required this.repos,
    required this.settings,
    required this.onCommit,
  });

  final ReposState repos;
  final AppSettings settings;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final ctrl = repos.current;
    final themeButton = Row(mainAxisSize: MainAxisSize.min, children: [
      IdeIconButton(
        icon: Theme.of(context).brightness == Brightness.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
        tooltip: 'Toggle Theme',
        onPressed: () => settings.setThemeMode(
            Theme.of(context).brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark),
      ),
      Builder(
        builder: (context) => IdeIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onPressed: () {
            final box = context.findRenderObject()! as RenderBox;
            showIdeMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
              IdeMenuItem('Network & Proxy...',
                  icon: Icons.lan_outlined, onTap: () => showNetworkDialog(context, repos)),
              IdeMenuItem('Accounts...',
                  icon: Icons.manage_accounts_outlined,
                  onTap: () => showAccountsDialog(context, repos.accounts)),
            ]);
          },
        ),
      ),
    ]);
    if (ctrl == null) {
      return _frame(context, [
        Text('EasyGit', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        themeButton,
      ]);
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final status = ctrl.status;
        final state = status?.state ?? RepoState.normal;
        final idle = ctrl.busy == null;
        return _frame(context, [
            // Where actions apply: plain text, switching happens in the sidebar
            // and the Branches tab. Capped so the Spacer pushes the actions right.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(ctrl.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text('  /  ', style: TextStyle(color: c.textDisabled)),
                Icon(Icons.call_split, size: 14, color: c.textSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(status == null ? '...' : ctrl.currentBranchLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary)),
                ),
                if (_aheadBehind(context, status) case final ab?) ab,
              ]),
            ),
            if (state != RepoState.normal) ...[
              const SizedBox(width: 8),
              _StateBadge(state: state),
              const SizedBox(width: 6),
              IdeButton(label: 'Continue', onPressed: ctrl.continueOperation),
              const SizedBox(width: 6),
              IdeButton(label: 'Abort', onPressed: ctrl.abortOperation),
            ],
            const Spacer(),
            _ActionButton(
              icon: Icons.sync,
              label: 'Fetch',
              tooltip: 'Fetch all remotes',
              onPressed: idle ? ctrl.fetch : null,
            ),
            _ActionButton(
              icon: Icons.south,
              label: 'Pull',
              color: c.accent,
              tooltip: 'Pull (${shortcutLabel('T')})',
              onPressed: idle ? () => ctrl.pull() : null,
            ),
            _ActionButton(
              icon: Icons.north,
              label: 'Push',
              color: c.success,
              tooltip: 'Push (${shortcutLabel('K', shift: true)})',
              onPressed: idle ? () => ctrl.push() : null,
            ),
            const ToolbarSeparator(),
            _ActionButton(
              icon: Icons.check,
              label: 'Commit',
              color: c.success,
              tooltip: 'Commit (${shortcutLabel('K')})',
              onPressed: onCommit,
            ),
            _ActionButton(
              icon: Icons.inventory_2_outlined,
              label: 'Stash',
              tooltip: 'Stash local changes',
              onPressed: idle && (status?.changes.isNotEmpty ?? false)
                  ? () async {
                      final message = await showInputDialog(context,
                          title: 'Stash Changes',
                          label: 'Message (optional):',
                          initial: 'WIP',
                          okLabel: 'Stash');
                      if (message != null) await ctrl.stash(message);
                    }
                  : null,
            ),
            _ActionButton(
              icon: Icons.add,
              label: 'Branch',
              tooltip: 'New branch from HEAD',
              onPressed: () async {
                final result = await showNewBranchDialog(context, ctrl.currentBranchLabel);
                if (result != null) {
                  await ctrl.createBranch(result.name, 'HEAD', checkout: result.checkout);
                }
              },
            ),
            const ToolbarSeparator(),
            IdeIconButton(
                icon: Icons.refresh, tooltip: 'Refresh (F5)', onPressed: repos.refreshAll),
            themeButton,
        ]);
      },
    );
  }

  /// The bar itself. With a custom title bar it also moves the window and
  /// carries the caption buttons.
  Widget _frame(BuildContext context, List<Widget> children) {
    final c = IdeColors.of(context);
    final ownChrome = customTitleBar && titleBarLeadingInset == 0;
    return WindowDragArea(
      child: Container(
        height: 44,
        color: c.panelBg,
        child: Row(children: [
          SizedBox(width: titleBarLeadingInset + (ownChrome ? 12 : 14)),
          if (ownChrome) ...[
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF3574F0), Color(0xFF9B5DE5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.call_split, color: Colors.white, size: 12),
            ),
            const SizedBox(width: 10),
          ],
          ...children,
          const SizedBox(width: 8),
          const WindowButtons(),
        ]),
      ),
    );
  }

  Widget? _aheadBehind(BuildContext context, RepoStatus? status) {
    if (status == null || (status.ahead == 0 && status.behind == 0)) return null;
    final c = IdeColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (status.behind > 0)
        Text(' ↓${status.behind}', style: TextStyle(fontSize: 12, color: c.accent)),
      if (status.ahead > 0)
        Text(' ↑${status.ahead}', style: TextStyle(fontSize: 12, color: c.success)),
    ]);
  }
}

/// Icon with a label, for the main Git actions.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: HoverBuilder(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        builder: (context, hovered) => GestureDetector(
          onTap: onPressed,
          child: Container(
            height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: hovered && enabled ? c.hover : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              Icon(icon, size: 16, color: enabled ? (color ?? c.icon) : c.textDisabled),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(fontSize: 12.5, color: enabled ? c.text : c.textDisabled)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final RepoState state;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final label = switch (state) {
      RepoState.merging => 'Merging',
      RepoState.rebasing => 'Rebasing',
      RepoState.cherryPicking => 'Cherry-picking',
      RepoState.reverting => 'Reverting',
      RepoState.normal => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.warning.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, color: c.warning)),
    );
  }
}
