import 'package:flutter/material.dart';

import '../git/models.dart';

const monoFontFamily = 'JetBrains Mono';
const monoFontFallback = [
  'Cascadia Mono',
  'Consolas',
  'SF Mono',
  'Menlo',
  'DejaVu Sans Mono',
  'Liberation Mono',
  'monospace',
];

/// Colors modelled on the JetBrains "New UI" Dark and Light themes.
@immutable
class IdeColors extends ThemeExtension<IdeColors> {
  const IdeColors({
    required this.editorBg,
    required this.panelBg,
    required this.popupBg,
    required this.splitter,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textDisabled,
    required this.icon,
    required this.selection,
    required this.selectionInactive,
    required this.hover,
    required this.accent,
    required this.inputBg,
    required this.buttonBorder,
    required this.success,
    required this.error,
    required this.warning,
    required this.fileModified,
    required this.fileAdded,
    required this.fileDeleted,
    required this.fileUnversioned,
    required this.fileRenamed,
    required this.fileConflict,
    required this.diffInserted,
    required this.diffDeleted,
    required this.diffModified,
    required this.diffFiller,
    required this.gutterText,
    required this.refLocal,
    required this.refRemote,
    required this.refTag,
    required this.refHead,
    required this.graphColors,
  });

  final Color editorBg;
  final Color panelBg;
  final Color popupBg;
  final Color splitter;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textDisabled;
  final Color icon;
  final Color selection;
  final Color selectionInactive;
  final Color hover;
  final Color accent;
  final Color inputBg;
  final Color buttonBorder;
  final Color success;
  final Color error;
  final Color warning;
  final Color fileModified;
  final Color fileAdded;
  final Color fileDeleted;
  final Color fileUnversioned;
  final Color fileRenamed;
  final Color fileConflict;
  final Color diffInserted;
  final Color diffDeleted;
  final Color diffModified;
  final Color diffFiller;
  final Color gutterText;
  final Color refLocal;
  final Color refRemote;
  final Color refTag;
  final Color refHead;
  final List<Color> graphColors;

  static const dark = IdeColors(
    editorBg: Color(0xFF1E1F22),
    panelBg: Color(0xFF2B2D30),
    popupBg: Color(0xFF2B2D30),
    splitter: Color(0xFF1E1F22),
    border: Color(0xFF393B40),
    text: Color(0xFFDFE1E5),
    textSecondary: Color(0xFF868A91),
    textDisabled: Color(0xFF5A5D63),
    icon: Color(0xFFCED0D6),
    selection: Color(0xFF2E436E),
    selectionInactive: Color(0xFF43454A),
    hover: Color(0xFF393B40),
    accent: Color(0xFF3574F0),
    inputBg: Color(0xFF1E1F22),
    buttonBorder: Color(0xFF4E5157),
    success: Color(0xFF5FB865),
    error: Color(0xFFDB5C5C),
    warning: Color(0xFFF2C55C),
    fileModified: Color(0xFF6897BB),
    fileAdded: Color(0xFF73BD79),
    fileDeleted: Color(0xFF8C8C8C),
    fileUnversioned: Color(0xFFD1675A),
    fileRenamed: Color(0xFF3EA4A4),
    fileConflict: Color(0xFFDB5C5C),
    diffInserted: Color(0xFF2A3E2D),
    diffDeleted: Color(0xFF4A2F31),
    diffModified: Color(0xFF263A55),
    diffFiller: Color(0xFF25262A),
    gutterText: Color(0xFF4B5059),
    refLocal: Color(0xFF73BD79),
    refRemote: Color(0xFFB18CD9),
    refTag: Color(0xFFE0C04E),
    refHead: Color(0xFFE0C04E),
    graphColors: [
      Color(0xFF5F9EE6),
      Color(0xFFDB8A3E),
      Color(0xFF6DBB5B),
      Color(0xFFC26FD1),
      Color(0xFFE0C04E),
      Color(0xFF4EC2B5),
      Color(0xFFE06C75),
      Color(0xFF9A9FF5),
    ],
  );

  static const light = IdeColors(
    editorBg: Color(0xFFFFFFFF),
    panelBg: Color(0xFFF7F8FA),
    popupBg: Color(0xFFFFFFFF),
    splitter: Color(0xFFEBECF0),
    border: Color(0xFFDFE1E5),
    text: Color(0xFF1E1F22),
    textSecondary: Color(0xFF6C707E),
    textDisabled: Color(0xFFA8ADBD),
    icon: Color(0xFF6C707E),
    selection: Color(0xFFD4E2FF),
    selectionInactive: Color(0xFFDFE1E5),
    hover: Color(0xFFEBECF0),
    accent: Color(0xFF3574F0),
    inputBg: Color(0xFFFFFFFF),
    buttonBorder: Color(0xFFC9CCD6),
    success: Color(0xFF208A3C),
    error: Color(0xFFDB3B4B),
    warning: Color(0xFFC27D04),
    fileModified: Color(0xFF0032A0),
    fileAdded: Color(0xFF067D17),
    fileDeleted: Color(0xFF6C707E),
    fileUnversioned: Color(0xFF993300),
    fileRenamed: Color(0xFF00808A),
    fileConflict: Color(0xFFC7222D),
    diffInserted: Color(0xFFDDF4DF),
    diffDeleted: Color(0xFFF9DCDC),
    diffModified: Color(0xFFDDE6FA),
    diffFiller: Color(0xFFF3F4F6),
    gutterText: Color(0xFFA8ADBD),
    refLocal: Color(0xFF208A3C),
    refRemote: Color(0xFF834DF0),
    refTag: Color(0xFFC27D04),
    refHead: Color(0xFFC27D04),
    graphColors: [
      Color(0xFF3574F0),
      Color(0xFFE08855),
      Color(0xFF55A76A),
      Color(0xFFA571E6),
      Color(0xFFD6AE58),
      Color(0xFF2FB1A6),
      Color(0xFFE55765),
      Color(0xFF6A7AE8),
    ],
  );

  static IdeColors of(BuildContext context) =>
      Theme.of(context).extension<IdeColors>() ?? dark;

  Color statusColor(ChangeKind kind) => switch (kind) {
        ChangeKind.modified || ChangeKind.typeChanged => fileModified,
        ChangeKind.added || ChangeKind.copied => fileAdded,
        ChangeKind.deleted => fileDeleted,
        ChangeKind.renamed => fileRenamed,
        ChangeKind.untracked => fileUnversioned,
        ChangeKind.conflicted => fileConflict,
      };

  @override
  IdeColors copyWith() => this;

  @override
  IdeColors lerp(ThemeExtension<IdeColors>? other, double t) =>
      other is IdeColors && t >= 0.5 ? other : this;
}

TextStyle monoStyle(BuildContext context, {double size = 13, Color? color}) => TextStyle(
      fontFamily: monoFontFamily,
      fontFamilyFallback: monoFontFallback,
      fontSize: size,
      height: 1.35,
      color: color ?? IdeColors.of(context).text,
    );

ThemeData buildIdeTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? IdeColors.dark : IdeColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      primary: c.accent,
      surface: c.panelBg,
      onSurface: c.text,
    ),
    scaffoldBackgroundColor: c.panelBg,
    canvasColor: c.panelBg,
    dividerColor: c.border,
    hoverColor: c.hover,
    focusColor: c.selection,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    visualDensity: VisualDensity.compact,
    textTheme: TextTheme(
      bodyLarge: TextStyle(fontSize: 14, color: c.text),
      bodyMedium: TextStyle(fontSize: 13, color: c.text),
      bodySmall: TextStyle(fontSize: 12, color: c.textSecondary),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
      labelLarge: TextStyle(fontSize: 13, color: c.text),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      textStyle: TextStyle(fontSize: 12, color: c.text),
      decoration: BoxDecoration(
        color: c.popupBg,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.popupBg,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      textStyle: TextStyle(fontSize: 13, color: c.text),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.border),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(8),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.all(c.textSecondary.withAlpha(90)),
    ),
    checkboxTheme: CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      side: BorderSide(color: c.buttonBorder, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.text,
      selectionColor: c.selection,
    ),
    extensions: [c],
  );
}
