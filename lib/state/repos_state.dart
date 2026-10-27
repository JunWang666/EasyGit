import 'dart:io';

import 'package:flutter/widgets.dart';

import '../git/git_repository.dart';
import '../hosting/hosting.dart';
import '../net/network.dart';
import 'accounts_store.dart';
import 'app_settings.dart';
import 'repo_controller.dart';

/// The repositories shown in the sidebar and which one is selected.
class ReposState extends ChangeNotifier {
  ReposState(this.settings, this.accounts, [NetworkSettings? network])
      : network = network ?? NetworkSettings() {
    _syncSelfHosted();
    accounts.addListener(_syncSelfHosted);
    // Leave an account page whose account was removed.
    accounts.addListener(() {
      if (account != null && !accounts.accounts.any((a) => a.id == account!.id)) {
        account = null;
        notifyListeners();
      }
    });
  }

  final AppSettings settings;
  final AccountsStore accounts;

  final NetworkSettings network;

  final List<RepoController> repos = [];
  RepoController? current;

  static const _publicHosts = {'github.com', 'gitlab.com', 'codeberg.org', 'gitea.com'};

  /// Self-hosted servers can bypass the proxy (see NetworkSettings).
  void _syncSelfHosted() => network.setSelfHostedHosts([
        for (final a in accounts.accounts)
          if (!_publicHosts.contains(a.host.toLowerCase())) a.host,
      ]);

  /// When set, the main area shows this account's repositories instead of
  /// the [current] repository.
  HostingAccount? account;

  void selectAccount(HostingAccount? value) {
    if (account?.id == value?.id) return;
    account = value;
    notifyListeners();
  }

  /// Sidebar paths that could not be opened (moved or deleted).
  final List<String> missing = [];

  /// Opens every repository saved in the sidebar.
  Future<void> restore() async {
    for (final path in settings.recent) {
      try {
        final ctrl = RepoController(await GitRepository.open(path), accounts);
        repos.add(ctrl);
      } catch (_) {
        missing.add(path);
      }
    }
    current = repos.where((r) => r.repo.root == settings.selectedRepository).firstOrNull ??
        repos.firstOrNull;
    notifyListeners();
    await current?.refreshAll();
    // Load the others in the background so the sidebar shows their state.
    for (final r in repos) {
      if (r != current) r.refreshSummary();
    }
  }

  /// Opens the repository containing [path] (throws GitException if there is
  /// none), adds it to the sidebar if needed and selects it.
  Future<RepoController> open(String path) async {
    final repo = await GitRepository.open(path);
    final existing = repos.where((r) => _samePath(r.repo.root, repo.root)).firstOrNull;
    if (existing != null) {
      select(existing);
      return existing;
    }
    final ctrl = RepoController(repo, accounts);
    repos.add(ctrl);
    missing.remove(path);
    await settings.addRecent(repo.root);
    select(ctrl);
    return ctrl;
  }

  void select(RepoController ctrl) {
    if (current == ctrl && account == null) return;
    account = null;
    if (current == ctrl) {
      notifyListeners();
      return;
    }
    current = ctrl;
    settings.setSelectedRepository(ctrl.repo.root);
    notifyListeners();
    ctrl.refreshAll();
  }

  /// Removes a repository from the sidebar. Nothing is deleted on disk.
  Future<void> remove(RepoController ctrl) async {
    final index = repos.indexOf(ctrl);
    if (index < 0) return;
    repos.removeAt(index);
    await settings.removeRecent(ctrl.repo.root);
    if (current == ctrl) {
      current = repos.isEmpty ? null : repos[index.clamp(0, repos.length - 1)];
      await settings.setSelectedRepository(current?.repo.root);
      current?.refreshAll();
    }
    notifyListeners();
    // Dispose once the widgets using it have left the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  }

  Future<void> forgetMissing(String path) async {
    missing.remove(path);
    await settings.removeRecent(path);
    notifyListeners();
  }

  void reorder(int from, int to) {
    if (from == to) return;
    final r = repos.removeAt(from);
    repos.insert(to > from ? to - 1 : to, r);
    settings.setRecent([for (final c in repos) c.repo.root, ...missing]);
    notifyListeners();
  }

  /// Refreshes the selected repository fully and the others' status.
  Future<void> refreshAll() async {
    for (final r in repos) {
      r == current ? r.refreshAll() : r.refreshSummary();
    }
  }

  static bool _samePath(String a, String b) {
    String norm(String p) {
      var s = p.replaceAll('\\', '/');
      while (s.length > 1 && s.endsWith('/')) {
        s = s.substring(0, s.length - 1);
      }
      return Platform.isWindows || Platform.isMacOS ? s.toLowerCase() : s;
    }

    return norm(a) == norm(b);
  }

  static bool samePath(String a, String b) => _samePath(a, b);
}
