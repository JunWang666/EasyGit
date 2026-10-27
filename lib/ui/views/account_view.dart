import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../hosting/hosting.dart';
import '../../state/repo_controller.dart';
import '../../state/repos_state.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../shell/repo_flows.dart';
import '../widgets/common.dart';

/// Main area for a signed-in account: its repositories, ready to clone.
class AccountView extends StatefulWidget {
  const AccountView({super.key, required this.account, required this.repos});

  final HostingAccount account;
  final ReposState repos;

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  late Future<List<RemoteRepo>> _list = _load();
  var _query = '';

  Future<List<RemoteRepo>> _load() =>
      widget.repos.accounts.apiFor(widget.account).repositories();

  /// The sidebar repository whose remotes point at [repo], if any.
  RepoController? _localClone(RemoteRepo repo) {
    final target = RemoteLocation.parse(repo.httpsUrl);
    if (target == null) return null;
    for (final r in widget.repos.repos) {
      for (final url in r.remoteUrls.values) {
        final loc = RemoteLocation.parse(url);
        if (loc != null &&
            loc.host == target.host &&
            loc.path.toLowerCase() == target.path.toLowerCase()) {
          return r;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final a = widget.account;
    if (!a.kind.hasApi) return _genericServer(context, a);
    return Container(
      color: c.editorBg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: c.panelBg,
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.hover, borderRadius: BorderRadius.circular(10)),
              child: Icon(hostingIcon(a.kind), size: 22, color: c.icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.username, style: Theme.of(context).textTheme.titleMedium),
                Text('${a.kind.label} · ${a.server}', style: TextStyle(color: c.textSecondary)),
              ]),
            ),
            IdeButton(
              label: 'Open in Browser',
              onPressed: () =>
                  launchUrl(Uri.parse('${a.server}/${a.username}'), mode: LaunchMode.externalApplication),
            ),
            const SizedBox(width: 6),
            IdeButton(
              label: 'Accounts...',
              onPressed: () => showAccountsDialog(context, widget.repos.accounts),
            ),
          ]),
        ),
        Container(height: 1, color: c.splitter),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 10, 6),
          child: Row(children: [
            Text('Repositories', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(width: 12),
            IdeTextField(
              width: 280,
              hint: 'Search repositories',
              prefixIcon: Icons.search,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
            const Spacer(),
            IdeIconButton(
              icon: Icons.refresh,
              tooltip: 'Reload',
              onPressed: () => setState(() => _list = _load()),
            ),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<RemoteRepo>>(
            future: _list,
            builder: (context, snapshot) {
              if (snapshot.hasError) return EmptyHint('${snapshot.error}');
              final all = snapshot.data;
              if (all == null) {
                return const Center(
                    child: SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final shown = all
                  .where((r) =>
                      _query.isEmpty ||
                      r.fullName.toLowerCase().contains(_query) ||
                      r.description.toLowerCase().contains(_query))
                  .toList();
              if (shown.isEmpty) {
                return EmptyHint(all.isEmpty ? 'No repositories' : 'No matching repositories');
              }
              return ListenableBuilder(
                listenable: widget.repos,
                builder: (context, _) => ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _row(shown[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }

  /// A self-hosted server account has no repository list, only credentials.
  Widget _genericServer(BuildContext context, HostingAccount a) {
    final c = IdeColors.of(context);
    final users = [
      for (final r in widget.repos.repos)
        if (r.remoteUrls.values.any((u) => RemoteLocation.parse(u)?.host == a.host.toLowerCase()) ||
            (r.lfs.endpoint?.contains(a.host) ?? false))
          r,
    ];
    return Container(
      color: c.editorBg,
      padding: const EdgeInsets.all(24),
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(hostingIcon(a.kind), size: 26, color: c.icon),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.server, style: Theme.of(context).textTheme.titleMedium),
              Text('Signed in as ${a.username}', style: TextStyle(color: c.textSecondary)),
            ]),
          ]),
          const SizedBox(height: 16),
          Text(
            'EasyGit gives these credentials to git and git-lfs whenever they connect to '
            '${a.host} over HTTPS: fetch, pull, push, clone and LFS transfers. Self-hosted '
            'servers have no repository list here; clone them by URL.',
          ),
          const SizedBox(height: 16),
          Text('Repositories in the sidebar that use this server',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          if (users.isEmpty)
            Text('None yet.', style: TextStyle(color: c.textSecondary))
          else
            for (final r in users)
              ListRow(
                height: 30,
                onTap: () => widget.repos.select(r),
                child: Row(children: [
                  Icon(Icons.folder_outlined, size: 15, color: c.icon),
                  const SizedBox(width: 8),
                  Text(r.name),
                ]),
              ),
          const SizedBox(height: 16),
          Row(children: [
            IdeButton(
              label: 'Clone by URL...',
              primary: true,
              onPressed: () => cloneRepositoryFlow(context, widget.repos, initialUrl: '${a.server}/'),
            ),
            const SizedBox(width: 8),
            IdeButton(
              label: 'Accounts...',
              onPressed: () => showAccountsDialog(context, widget.repos.accounts),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _row(RemoteRepo r) {
    final c = IdeColors.of(context);
    final local = _localClone(r);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(children: [
        Icon(r.isPrivate ? Icons.lock_outline : Icons.book_outlined, size: 17, color: c.icon),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (r.description.isNotEmpty)
                Text(r.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSecondary)),
            ],
          ),
        ),
        IdeIconButton(
          icon: Icons.open_in_new,
          tooltip: 'Open in browser',
          onPressed: () => launchUrl(Uri.parse(r.webUrl), mode: LaunchMode.externalApplication),
        ),
        const SizedBox(width: 6),
        if (local != null)
          IdeButton(label: 'Open', onPressed: () => widget.repos.select(local))
        else
          IdeButton(
            label: 'Clone...',
            primary: true,
            onPressed: () => cloneRepositoryFlow(context, widget.repos, initialUrl: r.httpsUrl),
          ),
      ]),
    );
  }
}
