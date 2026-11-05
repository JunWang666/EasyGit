import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../git/git_runner.dart';
import '../../state/app_settings.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../../system/open_requests.dart';
import '../settings/settings_page.dart';
import '../commit/commit_flow.dart';
import '../console/console_panel.dart';
import '../format.dart';
import '../views/account_view.dart';
import '../views/repo_views.dart';
import '../widgets/common.dart';
import 'main_toolbar.dart';
import 'repo_flows.dart';
import 'sidebar.dart';
import 'status_bar.dart';

/// Main window: toolbar, repository sidebar, the selected repository's view,
/// an optional Git console and the status bar.
class AppShell extends StatefulWidget {
  const AppShell(
      {super.key, required this.repos, required this.settings, required this.openRequests});

  final ReposState repos;
  final AppSettings settings;
  final OpenRequests openRequests;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _showConsole = false;
  late final AppLifecycleListener _lifecycle;

  ReposState get repos => widget.repos;

  @override
  void initState() {
    super.initState();
    // Pick up changes made outside the app when the window regains focus.
    _lifecycle = AppLifecycleListener(onResume: repos.refreshAll);
    widget.openRequests.addListener(_openRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
  }

  @override
  void dispose() {
    widget.openRequests.removeListener(_openRequested);
    _lifecycle.dispose();
    super.dispose();
  }

  var _opening = false;

  /// Opens folders from the command line or the Explorer context menu.
  Future<void> _openRequested() async {
    if (_opening) return;
    _opening = true;
    try {
      // Close the settings page or a dialog so the result is visible.
      Navigator.of(context).popUntil((r) => r.isFirst);
      for (var path = widget.openRequests.take();
          path != null && mounted;
          path = widget.openRequests.take()) {
        await openFolderFlow(context, repos, path);
      }
    } finally {
      _opening = false;
    }
  }

  void _focusCommit() {
    final ctrl = repos.current;
    if (ctrl == null) return;
    repos.select(ctrl);
    ctrl.setView(RepoView.changes);
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.messageFocus.requestFocus());
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final apple = isApplePlatform;
    SingleActivator primary(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, control: !apple, meta: apple, shift: shift);
    RepoController? ctrl() => repos.current;
    return {
      primary(LogicalKeyboardKey.keyK): _focusCommit,
      primary(LogicalKeyboardKey.keyT): () => ctrl()?.pull(),
      primary(LogicalKeyboardKey.keyK, shift: true): () => ctrl()?.push(),
      primary(LogicalKeyboardKey.enter): () {
        final r = ctrl();
        if (r != null) commitFlow(context, r);
      },
      for (final v in RepoView.values)
        primary(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + v.index)): () {
          final r = ctrl();
          if (r == null) return;
          repos.select(r);
          r.setView(v);
        },
      primary(LogicalKeyboardKey.backquote): () => setState(() => _showConsole = !_showConsole),
      const SingleActivator(LogicalKeyboardKey.f5): repos.refreshAll,
      primary(LogicalKeyboardKey.comma): () => showSettingsPage(context, repos),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.panelBg,
          body: ListenableBuilder(
            listenable: repos,
            builder: (context, _) {
              final ctrl = repos.current;
              return Stack(children: [
                Column(children: [
                  MainToolbar(repos: repos, settings: widget.settings, onCommit: _focusCommit),
                  Container(height: 1, color: c.splitter),
                  Expanded(
                    child: SplitPane(
                      axis: Axis.horizontal,
                      initialSize: 240,
                      minSize: 180,
                      minOther: 500,
                      first: Sidebar(repos: repos),
                      second: ctrl == null && repos.account == null
                          ? _EmptyState(repos: repos)
                          : _main(ctrl),
                    ),
                  ),
                  Container(height: 1, color: c.splitter),
                  if (ctrl != null)
                    StatusBar(
                      ctrl: ctrl,
                      consoleVisible: _showConsole,
                      onToggleConsole: () => setState(() => _showConsole = !_showConsole),
                      onBranchTap: () {
                        repos.select(ctrl);
                        ctrl.setView(RepoView.branches);
                      },
                    )
                  else
                    const SizedBox(height: 26),
                ]),
                if (ctrl != null)
                  Positioned(
                    right: 16,
                    bottom: 40,
                    child: _Notifications(
                      ctrl: ctrl,
                      onAction: (a) => a == NotificationAction.networkSettings
                          ? showSettingsPage(context, repos, section: SettingsSection.network)
                          : showSettingsPage(context, repos, section: SettingsSection.accounts),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  /// The account page if one is selected, else [ctrl]'s tabs.
  Widget _main(RepoController? ctrl) {
    final account = repos.account;
    if (account != null || ctrl == null) {
      return AccountView(key: ValueKey(account!.id), account: account, repos: repos);
    }
    final view = RepoMain(key: ObjectKey(ctrl), ctrl: ctrl, repos: repos);
    if (!_showConsole) return view;
    return SplitPane(
      axis: Axis.vertical,
      sizeOfSecond: true,
      initialSize: 200,
      minSize: 80,
      minOther: 200,
      first: view,
      second: ConsolePanel(ctrl: ctrl),
    );
  }
}

/// Shown when no repository has been added yet.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.repos});

  final ReposState repos;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return Container(
      color: c.editorBg,
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF3574F0), Color(0xFF9B5DE5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.call_split, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 16),
          Text('Welcome to EasyGit', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('Add a repository to get started. You can keep several in the sidebar.',
              textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
          if (!GitRunner.isSupported) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.warning.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.warning.withAlpha(120)),
              ),
              child: const Text(
                  'iPadOS does not allow running the git command line. This build needs a '
                  'native git backend (for example libgit2) to open repositories.'),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            IdeButton(
                label: 'Open Local Repository',
                primary: true,
                onPressed: () => openRepositoryFlow(context, repos)),
            IdeButton(
                label: 'Clone Repository', onPressed: () => cloneRepositoryFlow(context, repos)),
            IdeButton(
                label: 'Accounts',
                onPressed: () =>
                    showSettingsPage(context, repos, section: SettingsSection.accounts)),
          ]),
        ]),
      ),
    );
  }
}

/// Balloon notifications in the bottom-right corner.
class _Notifications extends StatelessWidget {
  const _Notifications({required this.ctrl, required this.onAction});

  final RepoController ctrl;
  final ValueChanged<NotificationAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final n in ctrl.notifications)
            Container(
              width: 360,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: c.popupBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(n.isError ? Icons.error_outline : Icons.check_circle_outline,
                    size: 18, color: n.isError ? c.error : c.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (n.hint != null) ...[
                      const SizedBox(height: 4),
                      Text(n.hint!, style: const TextStyle(fontSize: 12.5)),
                    ],
                    if (n.action != null) ...[
                      const SizedBox(height: 6),
                      IdeButton(
                        label: switch (n.action!) {
                          NotificationAction.networkSettings => 'Network Settings...',
                          NotificationAction.accounts => 'Accounts...',
                        },
                        onPressed: () {
                          ctrl.dismissNotification(n.id);
                          onAction(n.action!);
                        },
                      ),
                    ],
                    if (n.message.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: SingleChildScrollView(
                          child: SelectableText(n.message,
                              style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        ),
                      ),
                    ],
                  ]),
                ),
                IdeIconButton(
                  icon: Icons.close,
                  tooltip: 'Dismiss',
                  size: 22,
                  iconSize: 14,
                  onPressed: () => ctrl.dismissNotification(n.id),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
