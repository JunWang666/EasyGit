import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_settings.dart';
import '../../state/repos_state.dart';
import '../../system/explorer_menu.dart';
import '../../system/open_in.dart';
import '../../theme/ide_theme.dart';
import '../accounts/accounts_dialog.dart';
import '../widgets/common.dart';
import '../shell/window_chrome.dart';
import 'ide_choice.dart';
import 'network_dialog.dart';

enum SettingsSection {
  appearance('Appearance', Icons.palette_outlined),
  tools('External Tools', Icons.open_in_new),
  network('Network & Proxy', Icons.lan_outlined),
  accounts('Accounts', Icons.manage_accounts_outlined);

  const SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Opens the settings page over the main window, on [section].
Future<void> showSettingsPage(BuildContext context, ReposState repos,
        {SettingsSection section = SettingsSection.appearance}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 120),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (_, __, ___) => SettingsPage(repos: repos, initial: section),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ));

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.repos, this.initial = SettingsSection.appearance});

  final ReposState repos;
  final SettingsSection initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late var _section = widget.initial;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: c.editorBg,
          child: Column(children: [
            _header(context),
            Container(height: 1, color: c.splitter),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 220,
                  color: c.panelBg,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    for (final s in SettingsSection.values)
                      ListRow(
                        height: 32,
                        selected: s == _section,
                        onTap: () => setState(() => _section = s),
                        child: Row(children: [
                          Icon(s.icon, size: 16, color: c.icon),
                          const SizedBox(width: 10),
                          Text(s.label),
                        ]),
                      ),
                  ]),
                ),
                Container(width: 1, color: c.splitter),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_section.label, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 16),
                            KeyedSubtree(key: ValueKey(_section), child: _body()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = IdeColors.of(context);
    return WindowDragArea(
      child: Container(
        height: 44,
        color: c.panelBg,
        child: Row(children: [
          SizedBox(width: titleBarLeadingInset + 8),
          IdeIconButton(
            icon: Icons.arrow_back,
            tooltip: 'Back (Esc)',
            onPressed: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 6),
          Text('Settings', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          const WindowButtons(),
        ]),
      ),
    );
  }

  Widget _body() => switch (_section) {
        SettingsSection.appearance => _AppearanceSettings(settings: widget.repos.settings),
        SettingsSection.tools => _ToolsSettings(settings: widget.repos.settings),
        SettingsSection.network => NetworkSettingsPanel(repos: widget.repos),
        SettingsSection.accounts => AccountsPanel(store: widget.repos.accounts),
      };
}

class _AppearanceSettings extends StatelessWidget {
  const _AppearanceSettings({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _GroupLabel('Theme'),
        for (final (mode, label) in const [
          (ThemeMode.system, 'Follow system'),
          (ThemeMode.light, 'Light'),
          (ThemeMode.dark, 'Dark'),
        ])
          _OptionRow(
            radio: true,
            selected: settings.themeMode == mode,
            title: label,
            onTap: () => settings.setThemeMode(mode),
          ),
      ]),
    );
  }
}

class _ToolsSettings extends StatefulWidget {
  const _ToolsSettings({required this.settings});

  final AppSettings settings;

  @override
  State<_ToolsSettings> createState() => _ToolsSettingsState();
}

class _ToolsSettingsState extends State<_ToolsSettings> {
  List<InstalledIde>? _ides;

  AppSettings get settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect({bool refresh = false}) async {
    if (refresh) setState(() => _ides = null);
    final ides = await detectIdes(refresh: refresh);
    if (mounted) setState(() => _ides = ides);
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final ides = _ides ?? const <InstalledIde>[];
        final selected = preferredIde(settings, ides);
        final custom = settings.customIdePath;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _GroupLabel('Open in $fileManagerName'),
          if (canOpenFileManagerTab)
            _OptionRow(
              selected: settings.explorerOpenInTab,
              title: 'Open as a new tab in the most recent Explorer window',
              subtitle: 'Adds a tab to the Explorer window used last instead of opening a new '
                  'window. A new window opens when none is open, or on Windows 10.',
              onTap: () => settings.setExplorerOpenInTab(!settings.explorerOpenInTab),
            )
          else
            Text('Opens the repository folder in $fileManagerName.',
                style: TextStyle(color: c.textSecondary)),
          const SizedBox(height: 22),
          const _GroupLabel('Open in IDE'),
          if (_ides == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Looking for installed IDEs...'),
              ]),
            )
          else if (ides.isEmpty && custom == null)
            Text('No supported IDE was found. Choose its executable below.',
                style: TextStyle(color: c.textSecondary)),
          for (final ide in ides)
            _OptionRow(
              radio: true,
              selected: selected?.id == ide.id,
              title: ide.name,
              subtitle: ide.executable ?? ide.macApp,
              onTap: () => settings.setPreferredIde(ide.id),
            ),
          if (custom != null)
            _OptionRow(
              radio: true,
              selected: selected?.id == 'custom',
              title: '${customIde(custom).name} (custom)',
              subtitle: custom,
              onTap: () => settings.setPreferredIde('custom'),
            ),
          const SizedBox(height: 10),
          Row(children: [
            IdeButton(label: 'Choose Other...', onPressed: () => pickCustomIde(settings)),
            const SizedBox(width: 8),
            IdeButton(
                label: 'Rescan', onPressed: _ides == null ? null : () => _detect(refresh: true)),
          ]),
          if (ExplorerMenu.isSupported) ...[
            const SizedBox(height: 22),
            const _GroupLabel('Explorer context menu'),
            const _ExplorerMenuSettings(),
          ],
        ]);
      },
    );
  }
}

/// Installs or removes "Open in EasyGit" in the File Explorer context menu.
class _ExplorerMenuSettings extends StatefulWidget {
  const _ExplorerMenuSettings();

  @override
  State<_ExplorerMenuSettings> createState() => _ExplorerMenuSettingsState();
}

class _ExplorerMenuSettingsState extends State<_ExplorerMenuSettings> {
  var _loading = true;
  var _busy = false;
  String? _location;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final location = await ExplorerMenu.installedFor();
    if (!mounted) return;
    setState(() {
      _location = location;
      _loading = false;
    });
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final installed = _location != null;
    final here = ExplorerMenu.pointsHere(_location);
    final where = ExplorerMenu.usesModernMenu ? 'Windows 11 menu' : 'classic menu (Windows 10)';
    final status = _loading
        ? 'Checking...'
        : !installed
            ? 'Not installed.'
            : here
                ? 'Installed in the $where.'
                : 'Installed for another copy of EasyGit ($_location).';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Adds "Open in EasyGit" when you right-click a folder or the empty area of an open '
        'folder. EasyGit then opens the repository the folder is in, or lets you pick one of '
        'the repositories inside it.',
        style: TextStyle(fontSize: 12, color: c.textSecondary),
      ),
      const SizedBox(height: 8),
      Text(status),
      const SizedBox(height: 8),
      Row(children: [
        IdeButton(
          label: installed && !here ? 'Use This Copy' : (installed ? 'Reinstall' : 'Install'),
          primary: !installed || !here,
          onPressed: _loading || _busy ? null : () => _run(ExplorerMenu.install),
        ),
        if (installed) ...[
          const SizedBox(width: 8),
          IdeButton(
              label: 'Remove',
              onPressed: _loading || _busy ? null : () => _run(ExplorerMenu.uninstall)),
        ],
        if (_busy) ...[
          const SizedBox(width: 10),
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ]),
      if (_error != null) ...[
        const SizedBox(height: 8),
        SelectableText(_error!, style: TextStyle(fontSize: 12, color: c.error)),
      ],
    ]);
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}

/// A checkbox or radio button with a title and an optional explanation.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.radio = false,
  });

  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool radio;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final icon = radio
        ? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked)
        : (selected ? Icons.check_box : Icons.check_box_outline_blank);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 17, color: selected ? c.accent : c.buttonBorder),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
