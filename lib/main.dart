import 'package:flutter/material.dart';

import 'net/network.dart';
import 'state/accounts_store.dart';
import 'state/app_settings.dart';
import 'state/repos_state.dart';
import 'system/open_requests.dart';
import 'theme/ide_theme.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/window_chrome.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Listen for folders from other launches before anything slow happens.
  final openRequests = OpenRequests(args);
  await initWindowChrome();
  final settings = AppSettings();
  final accounts = AccountsStore();
  final network = NetworkSettings();
  // Network settings first: they configure every git process.
  await network.load();
  await Future.wait([settings.load(), accounts.load()]);
  final repos = ReposState(settings, accounts, network);
  runApp(EasyGitApp(settings: settings, repos: repos, openRequests: openRequests));
  await repos.restore();
  // Folders are opened once the sidebar is complete, so they are not added twice.
  openRequests.markReady();
}

class EasyGitApp extends StatelessWidget {
  const EasyGitApp(
      {super.key, required this.settings, required this.repos, required this.openRequests});

  final AppSettings settings;
  final ReposState repos;
  final OpenRequests openRequests;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'EasyGit',
        debugShowCheckedModeBanner: false,
        theme: buildIdeTheme(Brightness.light),
        darkTheme: buildIdeTheme(Brightness.dark),
        themeMode: settings.themeMode,
        home: AppShell(repos: repos, settings: settings, openRequests: openRequests),
      ),
    );
  }
}
