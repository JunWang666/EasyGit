import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Folders EasyGit was asked to open: from the command line (the Explorer
/// context menu starts `easygit.exe <folder>`) and from later launches, which
/// hand their folder to the running window (see windows/runner).
class OpenRequests extends ChangeNotifier {
  OpenRequests(List<String> args) {
    final folder = args.where((a) => !a.startsWith('-')).firstOrNull;
    if (folder != null) _queue.add(folder);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) {
        _queue.add(call.arguments as String);
        notifyListeners();
      }
    });
  }

  static const _channel = MethodChannel('easygit/instance');

  final List<String> _queue = [];

  /// False until the saved repositories are loaded.
  bool ready = false;

  void markReady() {
    ready = true;
    notifyListeners();
  }

  /// Takes the next folder to open, or null when there is none or the app is
  /// not [ready] yet.
  String? take() {
    if (!ready) return null;
    while (_queue.isNotEmpty) {
      final path = _queue.removeAt(0);
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }
}
