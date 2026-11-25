import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'dialogs.dart';

/// Directory picker that surfaces platform errors (missing entitlements,
/// plugin failures) in a dialog instead of letting them escape as unhandled
/// exceptions, which makes the invoking button look like it does nothing.
Future<String?> pickDirectory(BuildContext context, {String? dialogTitle}) async {
  try {
    return await FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
  } catch (e) {
    await _showPickerError(context, e);
    return null;
  }
}

/// Single-file picker with the same error reporting as [pickDirectory].
Future<String?> pickFile(
  BuildContext context, {
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  try {
    final result = await FilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: type,
      allowedExtensions: allowedExtensions,
    );
    return result?.files.singleOrNull?.path;
  } catch (e) {
    await _showPickerError(context, e);
    return null;
  }
}

Future<void> _showPickerError(BuildContext context, Object error) async {
  if (!context.mounted) return;
  await showConfirmDialog(context, title: 'Cannot Open File Picker', message: '$error');
}
