import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hosting/hosting.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../settings/settings_page.dart';
import '../lfs/lfs_dialog.dart';
import '../remotes/manage_remotes_dialog.dart';
import '../widgets/common.dart';
import '../widgets/menus.dart';
import '../../system/open_in.dart';
import '../repo/repo_settings_dialog.dart';
import 'repo_flows.dart';

/// Left sidebar: the repositories you work with and your online accounts.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.repos});

  final ReposState repos;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([repos, repos.accounts]),
      builder: (context, _) {
        final accounts = repos.accounts.accounts;
        return Container(
          color: c.panelBg,
          child: ListView(padding: const EdgeInsets.only(bottom: 12), children: [
            _SectionTitle(
              'REPOSITORIES',
              trailing: Builder(
                builder: (context) => IdeIconButton(
                  icon: Icons.add,
                  tooltip: 'Add Repository',
                  size: 24,
                  iconSize: 15,
                  onPressed: () => _addMenu(context),
                ),
              ),
            ),
            for (final r in repos.repos) _RepoRow(ctrl: r, repos: repos),
            for (final m in repos.missing) _missingRow(context, m),
            if (repos.repos.isEmpty && repos.missing.isEmpty)
              _hint(context, 'No repositories yet. Use + to open or clone one.'),
            const SizedBox(height: 10),
            _SectionTitle(
              'ONLINE ACCOUNTS',
              trailing: Builder(
                builder: (context) => IdeIconButton(
                  icon: Icons.add,
                  tooltip: 'Add GitHub, GitLab or Gitea account',
                  size: 24,
                  iconSize: 15,
                  onPressed: () async {
                    final box = context.findRenderObject()! as RenderBox;
                    final added = await pickAndAddAccount(
                        context, repos.accounts, box.localToGlobal(Offset(0, box.size.height)));
                    if (added != null) repos.selectAccount(added);
                  },
                ),
              ),
            ),
            for (final a in accounts) _accountRow(context, a),
            if (accounts.isEmpty)
              _hint(context, 'Sign in to GitHub, GitLab or Gitea to browse and clone your repositories.'),
          ]),
        );
      },
    );
  }

  Widget _hint(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
        child: Text(text,
            style: TextStyle(fontSize: 12, color: IdeColors.of(context).textSecondary)),
      );

  void _addMenu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    showIdeMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
      IdeMenuItem('Open Local Repository...',
          icon: Icons.folder_open_outlined, onTap: () => openRepositoryFlow(context, repos)),
      IdeMenuItem('Clone Repository...',
          icon: Icons.download_outlined, onTap: () => cloneRepositoryFlow(context, repos)),
    ]);
  }

  Widget _accountRow(BuildContext context, HostingAccount a) {
    final c = IdeColors.of(context);
    final selected = repos.account?.id == a.id;
    return ListRow(
      height: 40,
      selected: selected,
      onTap: () => repos.selectAccount(a),
      onContextMenu: (pos) => showIdeMenu(context, pos, [
        IdeMenuItem('Open ${a.server}',
            icon: Icons.open_in_new,
            onTap: () => launchUrl(Uri.parse(a.server), mode: LaunchMode.externalApplication)),
        IdeMenuItem('Manage Accounts...',
            icon: Icons.manage_accounts_outlined,
            onTap: () => showSettingsPage(context, repos, section: SettingsSection.accounts)),
      ]),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.hover,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(hostingIcon(a.kind), size: 15, color: c.icon),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
              Text('${a.kind.shortLabel} · ${a.host}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
            ],
          ),
        ),
        if (repos.accounts.tokenFor(a) == null)
          Tooltip(
            message: 'Token missing. Sign in again.',
            child: Icon(Icons.warning_amber, size: 14, color: c.warning),
          ),
      ]),
    );
  }


  Widget _missingRow(BuildContext context, String path) {
    final c = IdeColors.of(context);
    final name = path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? path;
    return ListRow(
      height: 30,
      onContextMenu: (pos) => showIdeMenu(context, pos, [
        IdeMenuItem('Remove from Sidebar',
            icon: Icons.close, onTap: () => repos.forgetMissing(path)),
      ]),
      child: Tooltip(
        message: '$path was not found',
        child: Row(children: [
          Icon(Icons.folder_off_outlined, size: 16, color: c.textDisabled),
          const SizedBox(width: 8),
          Text(name, style: TextStyle(color: c.textDisabled)),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return SizedBox(
      height: 32,
      child: Row(children: [
        const SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: c.textSecondary)),
        ),
        if (trailing != null) trailing!,
        const SizedBox(width: 4),
      ]),
    );
  }
}

/// A repository in the sidebar list with its branch and change count.
class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.ctrl, required this.repos});

  final RepoController ctrl;
  final ReposState repos;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final selected = repos.current == ctrl && repos.account == null;
    final color = c.graphColors[ctrl.name.hashCode.abs() % c.graphColors.length];
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final status = ctrl.status;
        final changes = status?.changes.length ?? 0;
        return ListRow(
          height: 42,
          selected: selected,
          onTap: () => repos.select(ctrl),
          onContextMenu: (pos) => _menu(context, pos),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
              child: Text(ctrl.name.isEmpty ? '?' : ctrl.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ctrl.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                  Row(children: [
                    Icon(Icons.call_split, size: 11, color: c.textSecondary),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(status == null ? '...' : status.headLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                    ),
                    if ((status?.behind ?? 0) > 0)
                      Text(' ↓${status!.behind}', style: TextStyle(fontSize: 11, color: c.accent)),
                    if ((status?.ahead ?? 0) > 0)
                      Text(' ↑${status!.ahead}', style: TextStyle(fontSize: 11, color: c.success)),
                  ]),
                ],
              ),
            ),
            if (ctrl.busy != null)
              const SizedBox(
                  width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
            else if (changes > 0)
              Tooltip(
                message: '$changes local change${changes == 1 ? '' : 's'}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.fileModified.withAlpha(60),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$changes', style: TextStyle(fontSize: 11, color: c.text)),
                ),
              ),
          ]),
        );
      },
    );
  }

  void _menu(BuildContext context, Offset pos) {
    final web = ctrl.webFor();
    showIdeMenu(context, pos, [
      IdeMenuItem('Show in $fileManagerName',
          icon: Icons.folder_outlined,
          onTap: () => openInFileManager(ctrl.repo.root, inTab: repos.settings.explorerOpenInTab)
              .catchError((Object e) => ctrl.reportError('Cannot open $fileManagerName', '$e'))),
      IdeMenuItem('Copy Path',
          icon: Icons.copy, onTap: () => Clipboard.setData(ClipboardData(text: ctrl.repo.root))),
      if (web != null)
        IdeMenuItem('Open on ${web.kind.shortLabel}',
            icon: hostingIcon(web.kind), onTap: () => ctrl.openUrl(web.home)),
      IdeMenuItem('Repository Settings...',
          icon: Icons.badge_outlined, onTap: () => showRepoSettingsDialog(context, ctrl)),
      IdeMenuItem('Manage Remotes...',
          icon: Icons.cloud_outlined, onTap: () => showManageRemotesDialog(context, ctrl)),
      IdeMenuItem('Git LFS...',
          icon: Icons.cloud_queue_outlined, onTap: () => showLfsDialog(context, ctrl)),
      const IdeMenuItem.divider(),
      IdeMenuItem('Remove from Sidebar',
          icon: Icons.close, onTap: () => repos.remove(ctrl)),
    ]);
  }
}
