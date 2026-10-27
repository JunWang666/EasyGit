import 'package:flutter/foundation.dart';

String _two(int v) => v.toString().padLeft(2, '0');

String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Relative-ish date like the IDE log: "Today 10:32", "Yesterday 09:01".
String formatLogDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today ${formatTime(d)}';
  if (diff == 1) return 'Yesterday ${formatTime(d)}';
  return '${d.year}/${_two(d.month)}/${_two(d.day)}, ${formatTime(d)}';
}

String formatFullDate(DateTime d) =>
    '${d.year}/${_two(d.month)}/${_two(d.day)} ${formatTime(d)}:${_two(d.second)}';

bool get isApplePlatform =>
    defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// Human-readable shortcut, e.g. "Ctrl+K" or "⌘K".
String shortcutLabel(String key, {bool shift = false, bool alt = false, bool primary = true}) {
  if (isApplePlatform) {
    return '${alt ? '⌥' : ''}${shift ? '⇧' : ''}${primary ? '⌘' : ''}$key';
  }
  return [if (primary) 'Ctrl', if (alt) 'Alt', if (shift) 'Shift', key].join('+');
}
