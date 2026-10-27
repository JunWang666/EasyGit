import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../hosting/hosting.dart';
import '../../state/accounts_store.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';

typedef CloneRequest = ({String url, String parent, String folder});

/// "Get from Version Control": clone by URL or from a signed-in account.
Future<CloneRequest?> showCloneDialog(BuildContext context, AccountsStore accounts,
        {String? initialUrl}) =>
    showDialog<CloneRequest>(
      context: context,
      builder: (context) => _CloneDialog(accounts: accounts, initialUrl: initialUrl),
    );

class _CloneDialog extends StatefulWidget {
  const _CloneDialog({required this.accounts, this.initialUrl});

  final AccountsStore accounts;
  final String? initialUrl;

  @override
  State<_CloneDialog> createState() => _CloneDialogState();
}

class _CloneDialogState extends State<_CloneDialog> {
  late final _url = TextEditingController(text: widget.initialUrl ?? '');

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) _urlChanged(widget.initialUrl!);
  }
  final _parent = TextEditingController();
  final _folder = TextEditingController();
  var _folderEdited = false;

  /// Selected source: null for "Repository URL", else an account id.
  String? _tab;

  @override
  void dispose() {
    _url.dispose();
    _parent.dispose();
    _folder.dispose();
    super.dispose();
  }

  void _setUrl(String url) {
    _url.text = url;
    _urlChanged(url);
    setState(() {});
  }

  void _urlChanged(String url) {
    if (_folderEdited) return;
    var name = url.trim().split(RegExp(r'[/:\\]')).where((s) => s.isNotEmpty).lastOrNull ?? '';
    if (name.endsWith('.git')) name = name.substring(0, name.length - 4);
    _folder.text = name;
  }

  Future<void> _browse() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Clone into');
    if (path != null) setState(() => _parent.text = path);
  }

  void _submit() {
    final url = _url.text.trim();
    final parent = _parent.text.trim();
    final folder = _folder.text.trim();
    if (url.isEmpty || parent.isEmpty || folder.isEmpty) return;
    Navigator.pop(context, (url: url, parent: parent, folder: folder));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.accounts,
      builder: (context, _) {
        final accounts = widget.accounts.accounts.where((a) => a.kind.hasApi).toList();
        final account = accounts.where((a) => a.id == _tab).firstOrNull;
        return IdeDialog(
          title: 'Clone Repository',
          width: 660,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _tabs(accounts),
              const SizedBox(height: 12),
              if (account == null) ...[
                const Text('URL:'),
                const SizedBox(height: 6),
                IdeTextField(
                  controller: _url,
                  autofocus: true,
                  hint: 'https://github.com/user/repo.git',
                  onChanged: _urlChanged,
                ),
              ] else
                _AccountRepos(
                  key: ValueKey(account.id),
                  api: widget.accounts.apiFor(account),
                  selectedUrl: _url.text,
                  onSelect: (repo) => _setUrl(repo.httpsUrl),
                ),
              const SizedBox(height: 12),
              const Text('Directory:'),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: IdeTextField(controller: _parent, hint: 'Parent folder')),
                const SizedBox(width: 6),
                IdeIconButton(
                    icon: Icons.folder_open_outlined, tooltip: 'Browse', onPressed: _browse),
              ]),
              const SizedBox(height: 12),
              const Text('Folder name:'),
              const SizedBox(height: 6),
              IdeTextField(controller: _folder, onChanged: (_) => _folderEdited = true),
            ],
          ),
          actions: [
            IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
            IdeButton(label: 'Clone', primary: true, onPressed: _submit),
          ],
        );
      },
    );
  }

  Widget _tabs(List<HostingAccount> accounts) {
    final c = IdeColors.of(context);
    Widget tab(String? id, IconData icon, String label) {
      final active = _tab == id;
      return HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: () => setState(() => _tab = id),
          child: Container(
            height: 30,
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: active ? c.selection : (hovered ? c.hover : null),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: c.icon),
              const SizedBox(width: 6),
              Text(label),
            ]),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        tab(null, Icons.link, 'Repository URL'),
        for (final a in accounts) tab(a.id, hostingIcon(a.kind), '${a.kind.shortLabel}: ${a.username}'),
        Builder(
          builder: (context) => IdeIconButton(
            icon: Icons.person_add_alt,
            tooltip: 'Add GitHub, GitLab or Gitea account',
            onPressed: () async {
              final box = context.findRenderObject()! as RenderBox;
              final pos = box.localToGlobal(Offset(0, box.size.height));
              final added = await pickAndAddAccount(context, widget.accounts, pos);
              if (added != null && mounted) setState(() => _tab = added.id);
            },
          ),
        ),
      ]),
    );
  }
}

/// Searchable list of an account's repositories.
class _AccountRepos extends StatefulWidget {
  const _AccountRepos(
      {super.key, required this.api, required this.selectedUrl, required this.onSelect});

  final HostingApi api;
  final String selectedUrl;
  final ValueChanged<RemoteRepo> onSelect;

  @override
  State<_AccountRepos> createState() => _AccountReposState();
}

class _AccountReposState extends State<_AccountRepos> {
  late Future<List<RemoteRepo>> _repos = widget.api.repositories();
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return Column(children: [
      Row(children: [
        Expanded(
          child: IdeTextField(
            hint: 'Search repositories',
            prefixIcon: Icons.search,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
        ),
        IdeIconButton(
          icon: Icons.refresh,
          tooltip: 'Reload',
          onPressed: () => setState(() => _repos = widget.api.repositories()),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        height: 260,
        decoration: BoxDecoration(
          color: c.editorBg,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(5),
        ),
        child: FutureBuilder<List<RemoteRepo>>(
          future: _repos,
          builder: (context, snapshot) {
            if (snapshot.hasError) return EmptyHint('${snapshot.error}');
            final repos = snapshot.data;
            if (repos == null) {
              return const Center(
                  child: SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final shown = repos
                .where((r) =>
                    _query.isEmpty ||
                    r.fullName.toLowerCase().contains(_query) ||
                    r.description.toLowerCase().contains(_query))
                .toList();
            if (shown.isEmpty) {
              return EmptyHint(repos.isEmpty ? 'No repositories' : 'No matching repositories');
            }
            return ListView.builder(
              itemCount: shown.length,
              itemExtent: 40,
              itemBuilder: (context, i) {
                final r = shown[i];
                return ListRow(
                  height: 40,
                  selected: r.httpsUrl == widget.selectedUrl,
                  onTap: () => widget.onSelect(r),
                  child: Row(children: [
                    Icon(r.isPrivate ? Icons.lock_outline : Icons.book_outlined,
                        size: 15, color: c.icon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (r.description.isNotEmpty)
                            Text(r.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
                        ],
                      ),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
