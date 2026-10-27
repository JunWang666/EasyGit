import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../git/models.dart';
import '../../theme/ide_theme.dart';

/// Rebuilds [builder] with the current hover state.
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({super.key, required this.builder, this.cursor = MouseCursor.defer});

  final Widget Function(BuildContext context, bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: widget.cursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: widget.builder(context, _hovered),
      );
}

/// Square toolbar button with hover highlight, like IntelliJ action buttons.
class IdeIconButton extends StatelessWidget {
  const IdeIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.size = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final bool selected;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: HoverBuilder(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        builder: (context, hovered) => GestureDetector(
          onTap: onPressed,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: selected
                  ? c.selectionInactive
                  : (hovered && enabled ? c.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(icon,
                size: iconSize, color: enabled ? (color ?? c.icon) : c.textDisabled),
          ),
        ),
      ),
    );
  }
}

/// Primary (filled blue) or secondary (outlined) dialog button.
class IdeButton extends StatelessWidget {
  const IdeButton({super.key, required this.label, required this.onPressed, this.primary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final enabled = onPressed != null;
    return HoverBuilder(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      builder: (context, hovered) => GestureDetector(
        onTap: onPressed,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary
                ? (enabled ? (hovered ? c.accent.withAlpha(220) : c.accent) : c.textDisabled)
                : (hovered && enabled ? c.hover : Colors.transparent),
            border: primary ? null : Border.all(color: c.buttonBorder),
            borderRadius: BorderRadius.circular(5),
          ),
          // Centre vertically but keep the button only as wide as its label.
          child: Align(
            widthFactor: 1,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: primary ? Colors.white : (enabled ? c.text : c.textDisabled))),
          ),
        ),
      ),
    );
  }
}

/// Title row of a tool window.
class PanelHeader extends StatelessWidget {
  const PanelHeader({super.key, required this.title, this.actions = const [], this.trailing});

  final String title;
  final List<Widget> actions;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(children: [
        const SizedBox(width: 10),
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall),
        ),
        const SizedBox(width: 8),
        ...actions,
        const Spacer(),
        if (trailing != null) trailing!,
        const SizedBox(width: 4),
      ]),
    );
  }
}

class ToolbarSeparator extends StatelessWidget {
  const ToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: IdeColors.of(context).border,
      );
}

/// Two panes separated by a draggable 1px splitter.
class SplitPane extends StatefulWidget {
  const SplitPane({
    super.key,
    required this.axis,
    required this.first,
    required this.second,
    this.initialSize = 300,
    this.minSize = 80,
    this.minOther = 120,
    this.sizeOfSecond = false,
  });

  final Axis axis;
  final Widget first;
  final Widget second;

  /// Initial extent of the sized pane (first, or second if [sizeOfSecond]).
  final double initialSize;
  final double minSize;
  final double minOther;
  final bool sizeOfSecond;

  @override
  State<SplitPane> createState() => _SplitPaneState();
}

class _SplitPaneState extends State<SplitPane> {
  late double _size = widget.initialSize;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final horizontal = widget.axis == Axis.horizontal;
    return LayoutBuilder(builder: (context, constraints) {
      final total = horizontal ? constraints.maxWidth : constraints.maxHeight;
      final maxSize = math.max(widget.minSize, total - widget.minOther - 1);
      final size = _size.clamp(widget.minSize, maxSize).toDouble();
      final firstSize = math.max(0.0, widget.sizeOfSecond ? total - size - 1 : size);
      final line = Container(
          width: horizontal ? 1 : null, height: horizontal ? null : 1, color: c.splitter);
      final panes = horizontal
          ? Row(children: [
              SizedBox(width: firstSize, child: widget.first),
              line,
              Expanded(child: widget.second),
            ])
          : Column(children: [
              SizedBox(height: firstSize, child: widget.first),
              line,
              Expanded(child: widget.second),
            ]);
      final handle = MouseRegion(
        cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (d) => setState(() {
            final delta = horizontal ? d.delta.dx : d.delta.dy;
            _size = size + (widget.sizeOfSecond ? -delta : delta);
          }),
        ),
      );
      return Stack(children: [
        Positioned.fill(child: panes),
        if (horizontal)
          Positioned(left: firstSize - 3, top: 0, bottom: 0, width: 7, child: handle)
        else
          Positioned(left: 0, right: 0, top: firstSize - 3, height: 7, child: handle),
      ]);
    });
  }
}

/// Icon + name + dimmed directory, colored by VCS status.
class FileChangeLabel extends StatelessWidget {
  const FileChangeLabel(
      {super.key, required this.change, this.showDirectory = true, this.lfs = false});

  final FileChange change;
  final bool showDirectory;

  /// Shows an "LFS" tag: the file is stored with Git LFS.
  final bool lfs;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final color = c.statusColor(change.kind);
    final strike = change.kind == ChangeKind.deleted;
    return Row(children: [
      Icon(fileIcon(change.name), size: 15, color: color.withAlpha(220)),
      const SizedBox(width: 6),
      Flexible(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: change.name,
                style: TextStyle(
                    color: color, decoration: strike ? TextDecoration.lineThrough : null)),
            if (showDirectory && change.directory.isNotEmpty)
              TextSpan(text: '  ${change.directory}', style: TextStyle(color: c.textSecondary)),
            if (change.oldPath != null && change.oldPath != change.path)
              TextSpan(
                  text: '  ← ${change.oldPath}', style: TextStyle(color: c.textSecondary)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
      if (lfs)
        Tooltip(
          message: 'Stored with Git LFS',
          child: Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border.all(color: c.accent.withAlpha(150)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text('LFS', style: TextStyle(fontSize: 9.5, color: c.accent)),
          ),
        ),
    ]);
  }
}

IconData fileIcon(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' || 'ico' => Icons.image_outlined,
    'md' || 'txt' || 'rst' => Icons.article_outlined,
    'json' || 'yaml' || 'yml' || 'toml' || 'xml' || 'ini' || 'lock' => Icons.data_object,
    'dart' || 'kt' || 'java' || 'js' || 'ts' || 'py' || 'go' || 'rs' || 'c' || 'cpp' || 'h' ||
    'cs' || 'swift' || 'rb' || 'php' || 'sh' || 'ps1' => Icons.code,
    _ => Icons.insert_drive_file_outlined,
  };
}

/// A compact single-line text field.
class IdeTextField extends StatelessWidget {
  const IdeTextField({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.prefixIcon,
    this.focusNode,
    this.width,
  });

  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final IconData? prefixIcon;
  final FocusNode? focusNode;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: BorderSide(color: c.buttonBorder),
    );
    return SizedBox(
      width: width,
      height: 28,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: 13, color: c.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: c.textSecondary),
          filled: true,
          fillColor: c.inputBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, size: 15, color: c.textSecondary),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 20),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: c.accent, width: 2)),
        ),
      ),
    );
  }
}

/// A single selectable row in a list or tree.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.child,
    this.selected = false,
    this.focused = true,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.height = 24,
    this.indent = 0,
  });

  final Widget child;
  final bool selected;
  final bool focused;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset globalPosition)? onContextMenu;
  final double height;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return HoverBuilder(
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown:
            onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
        onLongPressStart:
            onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
        child: Container(
          height: height,
          padding: EdgeInsets.only(left: 8 + indent, right: 8),
          color: selected
              ? (focused ? c.selection : c.selectionInactive)
              : (hovered ? c.hover.withAlpha(120) : null),
          child: child,
        ),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: IdeColors.of(context).textSecondary)),
        ),
      );
}
