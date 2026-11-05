import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../state/app_settings.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../system/open_in.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../settings/ide_choice.dart';
import '../settings/settings_page.dart';
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
      IdeIconButton(
        icon: Icons.settings_outlined,
        tooltip: 'Settings (${shortcutLabel(',')})',
        onPressed: () => showSettingsPage(context, repos),
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
          // The branch is shown in the sidebar and the status bar.
          const Text('EasyGit', style: TextStyle(fontWeight: FontWeight.w600)),
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
            icon: Icons.folder_open_outlined,
            label: fileManagerName,
            iconOnly: _narrow(context),
            tooltip: 'Open in $fileManagerName',
            onPressed: () => openInFileManager(ctrl.repo.root, inTab: settings.explorerOpenInTab)
                .catchError((Object e) => ctrl.reportError('Cannot open $fileManagerName', '$e')),
          ),
          _OpenInIdeButton(ctrl: ctrl, settings: settings),
          const ToolbarSeparator(),
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
            tooltip: (status?.behind ?? 0) > 0
                ? '${status!.behind} incoming commit${status.behind == 1 ? '' : 's'}. '
                    'Pull (${shortcutLabel('T')})'
                : 'Pull (${shortcutLabel('T')})',
            badge: status?.behind ?? 0,
            onPressed: idle ? () => ctrl.pull() : null,
          ),
          _ActionButton(
            icon: Icons.north,
            label: 'Push',
            color: c.success,
            tooltip: (status?.ahead ?? 0) > 0
                ? '${status!.ahead} outgoing commit${status.ahead == 1 ? '' : 's'}. '
                    'Push (${shortcutLabel('K', shift: true)})'
                : 'Push (${shortcutLabel('K', shift: true)})',
            badge: status?.ahead ?? 0,
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
          IdeIconButton(icon: Icons.refresh, tooltip: 'Refresh (F5)', onPressed: repos.refreshAll),
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
}

/// Below this width the "open in" buttons drop their labels so the Git
/// actions keep their room.
bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width < 1200;

/// Icon with a label, for the main Git actions.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.iconOnly = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;

  /// A count shown in a pill after the label (commits to pull or push).
  final int badge;

  /// Hides [label], for narrow windows; the tooltip still names the action.
  final bool iconOnly;
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
              if (!iconOnly) ...[
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(fontSize: 12.5, color: enabled ? c.text : c.textDisabled)),
              ],
              if (badge > 0) ...[
                const SizedBox(width: 5),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color ?? c.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(badge > 999 ? '999+' : '$badge',
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Open in IDE" split button: the left part opens the repository in the
/// chosen IDE, the arrow picks which IDE (remembered in [AppSettings]).
class _OpenInIdeButton extends StatefulWidget {
  const _OpenInIdeButton({required this.ctrl, required this.settings});

  final RepoController ctrl;
  final AppSettings settings;

  @override
  State<_OpenInIdeButton> createState() => _OpenInIdeButtonState();
}

class _OpenInIdeButtonState extends State<_OpenInIdeButton> {
  List<InstalledIde> _ides = const [];
  final _arrowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect({bool refresh = false}) async {
    final ides = await detectIdes(refresh: refresh);
    if (mounted) setState(() => _ides = ides);
  }

  InstalledIde? get _selected => preferredIde(widget.settings, _ides);

  Future<void> _open(InstalledIde ide) async {
    try {
      await openInIde(ide, widget.ctrl.repo.root);
    } catch (e) {
      widget.ctrl.reportError('Cannot open ${ide.name}', '$e');
    }
  }

  Future<void> _choose(InstalledIde ide) async {
    await widget.settings.setPreferredIde(ide.id);
    await _open(ide);
  }

  Future<void> _chooseOther() async {
    final ide = await pickCustomIde(widget.settings);
    if (ide != null) await _open(ide);
  }

  void _showMenu() {
    final box = _arrowKey.currentContext!.findRenderObject()! as RenderBox;
    final selected = _selected;
    final custom = widget.settings.customIdePath;
    showIdeMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
      if (_ides.isEmpty) const IdeMenuItem('No IDE found', enabled: false),
      for (final ide in _ides)
        IdeMenuItem(ide.name,
            icon: selected?.id == ide.id ? Icons.check : null, onTap: () => _choose(ide)),
      if (custom != null)
        IdeMenuItem(customIde(custom).name,
            icon: selected?.id == 'custom' ? Icons.check : null,
            onTap: () => _choose(customIde(custom))),
      const IdeMenuItem.divider(),
      IdeMenuItem('Choose Other...', icon: Icons.more_horiz, onTap: _chooseOther),
      IdeMenuItem('Rescan Installed IDEs',
          icon: Icons.refresh, onTap: () => _detect(refresh: true)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final ide = _selected;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          _ActionButton(
            icon: Icons.code,
            label: ide?.name ?? 'Open in IDE',
            iconOnly: _narrow(context),
            tooltip: ide == null ? 'Choose an IDE' : 'Open in ${ide.name}',
            onPressed: ide == null ? _showMenu : () => _open(ide),
          ),
          IdeIconButton(
            key: _arrowKey,
            icon: Icons.arrow_drop_down,
            tooltip: 'Choose IDE',
            onPressed: _showMenu,
          ),
        ]);
      },
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
