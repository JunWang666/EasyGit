import 'dart:io';

/// "Open in EasyGit" in the File Explorer context menu, for every folder and
/// for the background of an open folder.
///
/// Windows 11's context menu needs a packaged handler: the sparse package in
/// `<install>\shell` (see windows/shell_extension). Windows 10 has no such
/// menu, so a classic registry verb is used there.
class ExplorerMenu {
  static const packageName = 'EasyGit.ExplorerMenu';

  static bool get isSupported => Platform.isWindows;

  /// Windows 11 is build 22000 and later.
  static bool get usesModernMenu {
    final build = RegExp(r'Build (\d+)').firstMatch(Platform.operatingSystemVersion)?.group(1);
    return (int.tryParse(build ?? '') ?? 0) >= 22000;
  }

  static String get _bundleDir => File(Platform.resolvedExecutable).parent.path;
  static String get _exe => Platform.resolvedExecutable;

  static const _classicKeys = [
    r'HKCU\Software\Classes\Directory\shell\EasyGit',
    r'HKCU\Software\Classes\Directory\Background\shell\EasyGit',
  ];

  /// Where the installed menu starts EasyGit from, or null when it is not
  /// installed.
  static Future<String?> installedFor() async {
    if (!usesModernMenu) {
      final r = await Process.run('reg', ['query', '${_classicKeys.first}\\command', '/ve']);
      if (r.exitCode != 0) return null;
      final m = RegExp(r'"([^"]+easygit\.exe)"', caseSensitive: false).firstMatch('${r.stdout}');
      return m == null ? '' : File(m.group(1)!).parent.path;
    }
    // Prints "<external path>|<install location>", or nothing when missing.
    final r =
        await _powershell('\$p = Get-AppxPackage -Name $packageName | Select-Object -First 1; '
            'if (\$p) { "\$(\$p.EffectiveExternalPath)|\$(\$p.InstallLocation)" }');
    final out = '${r.stdout}'.trim();
    if (r.exitCode != 0 || !out.contains('|')) return null;
    final [external, location] = out.split('|');
    if (external.isNotEmpty) return external;
    // Not every Windows build reports the external path. A registered
    // manifest lives in <install>\shell, so its parent is the install folder.
    final shell = location.replaceFirst(RegExp(r'[\\/]+$'), '');
    if (shell.toLowerCase().endsWith(r'\shell')) return File(shell).parent.path;
    return '';
  }

  /// Whether the installed menu starts this copy of EasyGit.
  static bool pointsHere(String? location) =>
      location != null && (location.isEmpty || _same(location, _bundleDir));

  /// Installs or updates the menu for this copy of EasyGit. Returns an error
  /// message, or null on success.
  static Future<String?> install() async {
    if (!usesModernMenu) return _installClassic();
    final shell = '$_bundleDir\\shell';
    final signed = File('$shell\\$packageName.msix');
    final manifest = File('$shell\\AppxManifest.xml');
    if (!manifest.existsSync() && !signed.existsSync()) {
      return 'The context menu files are missing from $shell. Reinstall EasyGit.';
    }
    final script = signed.existsSync()
        ? "Add-AppxPackage -Path '${_q(signed.path)}' -ExternalLocation '${_q(_bundleDir)}' "
            '-ForceUpdateFromAnyVersion'
        : "Add-AppxPackage -Register '${_q(manifest.path)}' -ExternalLocation '${_q(_bundleDir)}' "
            '-ForceUpdateFromAnyVersion';
    final r = await _powershell("\$ErrorActionPreference = 'Stop'; $script");
    if (r.exitCode == 0) return null;
    final err = '${r.stderr}'.trim();
    if (!signed.existsSync() &&
        (err.contains('0x80073CFF') || err.contains('developer') || err.contains('0x80073D2E'))) {
      return 'Windows only accepts this unsigned context menu with Developer Mode on '
          '(Settings > System > For developers). Release builds ship a signed package instead.\n\n'
          '$err';
    }
    return err.isEmpty ? 'Add-AppxPackage failed (${r.exitCode}).' : err;
  }

  /// Removes the menu. Returns an error message, or null on success.
  static Future<String?> uninstall() async {
    if (!usesModernMenu) {
      for (final k in _classicKeys) {
        await Process.run('reg', ['delete', k, '/f']);
      }
      return null;
    }
    final r = await _powershell(
        "\$ErrorActionPreference = 'Stop'; Get-AppxPackage -Name $packageName | Remove-AppxPackage");
    return r.exitCode == 0 ? null : '${r.stderr}'.trim();
  }

  static Future<String?> _installClassic() async {
    for (final (key, arg) in [(_classicKeys[0], '%1'), (_classicKeys[1], '%V')]) {
      for (final args in [
        ['add', key, '/ve', '/d', 'Open in EasyGit', '/f'],
        ['add', key, '/v', 'Icon', '/d', '"$_exe",0', '/f'],
        ['add', '$key\\command', '/ve', '/d', '"$_exe" "$arg"', '/f'],
      ]) {
        final r = await Process.run('reg', args);
        if (r.exitCode != 0) return '${r.stderr}'.trim();
      }
    }
    return null;
  }

  static Future<ProcessResult> _powershell(String script) => Process.run('powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script]);

  static String _q(String s) => s.replaceAll("'", "''");

  static bool _same(String a, String b) =>
      a.replaceAll('/', r'\').replaceFirst(RegExp(r'\\$'), '').toLowerCase() ==
      b.replaceAll('/', r'\').replaceFirst(RegExp(r'\\$'), '').toLowerCase();
}
