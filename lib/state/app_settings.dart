import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent app preferences: recent repositories and theme.
class AppSettings extends ChangeNotifier {
  static const _recentKey = 'recentRepositories';
  static const _themeKey = 'themeMode';
  static const _selectedKey = 'selectedRepository';

  /// Repositories shown in the sidebar, in order.
  List<String> recent = [];
  String? selectedRepository;
  ThemeMode themeMode = ThemeMode.system;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      recent = prefs.getStringList(_recentKey) ?? [];
      selectedRepository = prefs.getString(_selectedKey);
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
