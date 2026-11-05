import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../../state/app_settings.dart';
import '../../system/open_in.dart';

/// The IDE "Open in IDE" uses: the saved choice, else the first one found.
InstalledIde? preferredIde(AppSettings s, List<InstalledIde> detected) {
  if (s.preferredIde == 'custom' && s.customIdePath != null) return customIde(s.customIdePath!);
  for (final ide in detected) {
    if (ide.id == s.preferredIde) return ide;
  }
  return s.preferredIde == null && detected.isNotEmpty ? detected.first : null;
}

/// Asks for an editor executable. Saves it as the preferred IDE and returns
/// it, or null if cancelled.
Future<InstalledIde?> pickCustomIde(AppSettings settings) async {
  final result = await FilePicker.pickFiles(
    dialogTitle: 'Choose IDE executable',
    type: Platform.isWindows ? FileType.custom : FileType.any,
    allowedExtensions: Platform.isWindows ? const ['exe', 'cmd', 'bat'] : null,
  );
  final path = result?.files.singleOrNull?.path;
  if (path == null) return null;
  await settings.setPreferredIde('custom', customPath: path);
  return customIde(path);
}
