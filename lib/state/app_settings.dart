import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent app preferences: recent repositories and theme.
class AppSettings extends ChangeNotifier {
  static const _recentKey = 'recentRepositories';
  static const _themeKey = 'themeMode';
  static const _selectedKey = 'selectedRepository';
  static const _ideKey = 'preferredIde';
  static const _customIdeKey = 'customIdePath';
  static const _explorerTabKey = 'explorerOpenInTab';

  /// Repositories shown in the sidebar, in order.
  List<String> recent = [];
  String? selectedRepository;
  ThemeMode themeMode = ThemeMode.system;

  /// Id of the IDE used by "Open in IDE" (`custom` for [customIdePath]).
  String? preferredIde;
  String? customIdePath;

  /// "Open in Explorer" adds a tab to the most recent Explorer window instead
  /// of opening a new one.
  bool explorerOpenInTab = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      recent = prefs.getStringList(_recentKey) ?? [];
      selectedRepository = prefs.getString(_selectedKey);
      preferredIde = prefs.getString(_ideKey);
      customIdePath = prefs.getString(_customIdeKey);
      explorerOpenInTab = prefs.getBool(_explorerTabKey) ?? false;
      final theme = prefs.getInt(_themeKey) ?? 0;
      themeMode = ThemeMode.values[theme.clamp(0, ThemeMode.values.length - 1)];
    } catch (_) {
      // Preferences are a convenience; start empty if unavailable.
    }
    notifyListeners();
  }

  /// Appends [path] to the sidebar list if it is not there yet.
  Future<void> addRecent(String path) async {
    if (recent.contains(path)) return;
    recent = [...recent, path];
    notifyListeners();
    await _save();
  }

  Future<void> setRecent(List<String> paths) async {
    recent = paths;
    notifyListeners();
    await _save();
  }

  Future<void> setSelectedRepository(String? path) async {
    selectedRepository = path;
    await _save();
  }

  Future<void> removeRecent(String path) async {
    recent = recent.where((p) => p != path).toList();
    notifyListeners();
    await _save();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _save();
  }

  /// Remembers the IDE for "Open in IDE"; [customPath] goes with id `custom`.
  Future<void> setPreferredIde(String id, {String? customPath}) async {
    preferredIde = id;
    if (customPath != null) customIdePath = customPath;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ideKey, id);
      final custom = customIdePath;
      if (custom != null) await prefs.setString(_customIdeKey, custom);
    } catch (_) {}
  }

  Future<void> setExplorerOpenInTab(bool value) async {
    explorerOpenInTab = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_explorerTabKey, value);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, recent);
      await prefs.setInt(_themeKey, themeMode.index);
      final selected = selectedRepository;
      selected == null ? await prefs.remove(_selectedKey) : await prefs.setString(_selectedKey, selected);
    } catch (_) {}
  }
}
