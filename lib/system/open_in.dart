import 'dart:io';

import 'explorer_windows.dart';

String _native(String path) => Platform.isWindows ? path.replaceAll('/', r'\') : path;

/// Whether the file manager can open a tab in an existing window (Windows 11
/// Explorer; on Windows 10 it falls back to a new window).
bool get canOpenFileManagerTab => Platform.isWindows;

/// Opens [path] in the system file manager. With [inTab] on Windows it opens
/// as a new tab of the most recent Explorer window, if there is one.
Future<void> openInFileManager(String path, {bool inTab = false}) async {
  if (Platform.isWindows) {
    if (inTab && await openInRecentExplorerTab(_native(path))) return;
    // explorer.exe exits with 1 even on success, so the exit code is ignored.
    await Process.start('explorer.exe', [_native(path)], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.start('open', [path], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
  }
}

/// What the file manager is called on this platform.
String get fileManagerName => Platform.isWindows
    ? 'Explorer'
    : Platform.isMacOS
        ? 'Finder'
        : 'Files';

/// An editor or IDE that can open a folder.
class Ide {
  const Ide(this.id, this.name,
      {this.commands = const [], this.windowsPaths = const [], this.macApp});

  final String id;
  final String name;

  /// Launcher names looked up on PATH.
  final List<String> commands;

  /// Install locations on Windows, relative to `%LOCALAPPDATA%` or
  /// `%ProgramFiles%` (both are tried).
  final List<String> windowsPaths;

  /// Application bundle name on macOS, e.g. `Visual Studio Code`.
  final String? macApp;
}

const knownIdes = <Ide>[
  Ide('vscode', 'VS Code',
      commands: ['code'],
      windowsPaths: [r'Programs\Microsoft VS Code\Code.exe', r'Microsoft VS Code\Code.exe'],
      macApp: 'Visual Studio Code'),
  Ide('cursor', 'Cursor',
      commands: ['cursor'], windowsPaths: [r'Programs\cursor\Cursor.exe'], macApp: 'Cursor'),
  Ide('windsurf', 'Windsurf',
      commands: ['windsurf'], windowsPaths: [r'Programs\Windsurf\Windsurf.exe'], macApp: 'Windsurf'),
  Ide('zed', 'Zed', commands: ['zed'], windowsPaths: [r'Programs\Zed\Zed.exe'], macApp: 'Zed'),
  Ide('idea', 'IntelliJ IDEA',
      commands: ['idea', 'idea64'],
      windowsPaths: [r'JetBrains\Toolbox\scripts\idea.cmd'],
      macApp: 'IntelliJ IDEA'),
  Ide('webstorm', 'WebStorm',
      commands: ['webstorm', 'webstorm64'],
      windowsPaths: [r'JetBrains\Toolbox\scripts\webstorm.cmd'],
      macApp: 'WebStorm'),
  Ide('pycharm', 'PyCharm',
      commands: ['pycharm', 'pycharm64'],
      windowsPaths: [r'JetBrains\Toolbox\scripts\pycharm.cmd'],
      macApp: 'PyCharm'),
  Ide('goland', 'GoLand',
      commands: ['goland', 'goland64'],
      windowsPaths: [r'JetBrains\Toolbox\scripts\goland.cmd'],
      macApp: 'GoLand'),
  Ide('rider', 'Rider',
      commands: ['rider', 'rider64'],
      windowsPaths: [r'JetBrains\Toolbox\scripts\rider.cmd'],
      macApp: 'Rider'),
  Ide('clion', 'CLion',
      commands: ['clion', 'clion64'],
      windowsPaths: [r'JetBrains\Toolbox\scripts\clion.cmd'],
      macApp: 'CLion'),
  Ide('studio', 'Android Studio',
      commands: ['studio', 'studio64'],
      windowsPaths: [r'Android\Android Studio\bin\studio64.exe'],
      macApp: 'Android Studio'),
  Ide('fleet', 'Fleet',
      commands: ['fleet'], windowsPaths: [r'JetBrains\Toolbox\scripts\fleet.cmd'], macApp: 'Fleet'),
  Ide('sublime', 'Sublime Text',
      commands: ['subl'],
      windowsPaths: [r'Sublime Text\sublime_text.exe', r'Sublime Text 3\sublime_text.exe'],
      macApp: 'Sublime Text'),
];

/// An IDE found on this machine and how to start it.
class InstalledIde {
  const InstalledIde(this.id, this.name, this.executable, {this.macApp});

  final String id;
  final String name;
  final String? executable;
  final String? macApp;
}

List<InstalledIde>? _detected;

/// The known IDEs installed on this machine. Cached after the first call;
/// pass [refresh] to look again.
Future<List<InstalledIde>> detectIdes({bool refresh = false}) async {
  if (_detected != null && !refresh) return _detected!;
  final found = <InstalledIde>[];
  for (final ide in knownIdes) {
    final hit = await _locate(ide);
    if (hit != null) found.add(hit);
  }
  if (Platform.isWindows) {
    final vs = await _visualStudio();
    if (vs != null) found.add(vs);
  }
  return _detected = found;
}

/// Visual Studio has no fixed path; vswhere reports the newest install.
Future<InstalledIde?> _visualStudio() async {
  final pf86 = Platform.environment['ProgramFiles(x86)'];
  if (pf86 == null) return null;
  final vswhere = '$pf86\\Microsoft Visual Studio\\Installer\\vswhere.exe';
  if (!File(vswhere).existsSync()) return null;
  try {
    final r = await Process.run(vswhere, ['-latest', '-prerelease', '-property', 'productPath']);
    final path = '${r.stdout}'.trim();
    if (r.exitCode != 0 || path.isEmpty || !File(path).existsSync()) return null;
    return InstalledIde('vs', 'Visual Studio', path);
  } catch (_) {
    return null;
  }
}

Future<InstalledIde?> _locate(Ide ide) async {
  if (Platform.isMacOS && ide.macApp != null) {
    for (final dir in ['/Applications', '${Platform.environment['HOME']}/Applications']) {
      if (Directory('$dir/${ide.macApp}.app').existsSync()) {
        return InstalledIde(ide.id, ide.name, null, macApp: ide.macApp);
      }
    }
  }
  if (Platform.isWindows) {
    final env = Platform.environment;
    final roots = [env['LOCALAPPDATA'], env['ProgramFiles'], env['ProgramFiles(x86)']]
        .whereType<String>();
    for (final root in roots) {
      for (final rel in ide.windowsPaths) {
        final f = '$root\\$rel';
        if (File(f).existsSync()) return InstalledIde(ide.id, ide.name, f);
      }
    }
  }
  for (final cmd in ide.commands) {
    final exe = await _which(cmd);
    if (exe != null) return InstalledIde(ide.id, ide.name, exe);
  }
  return null;
}

Future<String?> _which(String command) async {
  try {
    final r = Platform.isWindows
        ? await Process.run('where', [command])
        : await Process.run('which', [command]);
    if (r.exitCode != 0) return null;
    final lines = '${r.stdout}'.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty);
    if (lines.isEmpty) return null;
    // On Windows prefer a launcher that can be run directly.
    return lines.firstWhere(
        (l) => !Platform.isWindows || RegExp(r'\.(exe|cmd|bat)$', caseSensitive: false).hasMatch(l),
        orElse: () => lines.first).trim();
  } catch (_) {
    return null;
  }
}

/// Opens [folder] with [ide]. Throws a [ProcessException] if it cannot start.
Future<void> openInIde(InstalledIde ide, String folder) async {
  if (ide.macApp != null) {
    await Process.start('open', ['-a', ide.macApp!, folder], mode: ProcessStartMode.detached);
    return;
  }
  final exe = ide.executable!;
  final script = RegExp(r'\.(cmd|bat)$', caseSensitive: false).hasMatch(exe);
  await Process.start(exe, [_native(folder)],
      mode: ProcessStartMode.detached, runInShell: Platform.isWindows && script);
}

/// A user-chosen executable, used as an IDE.
InstalledIde customIde(String executable) {
  final name = _baseName(executable);
  if (Platform.isMacOS && executable.endsWith('.app')) {
    return InstalledIde('custom', name, null, macApp: executable);
  }
  return InstalledIde('custom', name, executable);
}

String _baseName(String path) {
  final name = path.split(RegExp(r'[\/]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
