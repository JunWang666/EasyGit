import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../theme/ide_theme.dart';

/// True once the native title bar has been hidden and the app draws its own.
bool customTitleBar = false;

/// Hides the native title bar on desktop. The toolbar then acts as the
/// title bar (see [WindowDragArea] and [WindowButtons]).
Future<void> initWindowChrome() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
  try {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'EasyGit',
        minimumSize: Size(900, 560),
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    customTitleBar = true;
  } catch (e) {
    // Keep the native title bar if the platform side is unavailable.
    debugPrint('Custom title bar unavailable: $e');
  }
}

/// Space reserved for the macOS traffic-light buttons.
double get titleBarLeadingInset => customTitleBar && Platform.isMacOS ? 72 : 0;

/// Drag to move the window; double-click to maximize or restore.
class WindowDragArea extends StatelessWidget {
  const WindowDragArea({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!customTitleBar) return child;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      child: child,
    );
  }
}

/// Minimize, maximize/restore and close, for Windows and Linux.
class WindowButtons extends StatefulWidget {
  const WindowButtons({super.key});

  @override
  State<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends State<WindowButtons> with WindowListener {
  var _maximized = false;

  @override
  void initState() {
    super.initState();
    if (!customTitleBar) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    if (customTitleBar) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowRestore() => windowManager.isMaximized().then((v) {
        if (mounted) setState(() => _maximized = v);
      });

  @override
  Widget build(BuildContext context) {
    if (!customTitleBar || Platform.isMacOS) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _CaptionButton(
        icon: Icons.remove,
        tooltip: 'Minimize',
        onPressed: windowManager.minimize,
      ),
      _CaptionButton(
        icon: _maximized ? Icons.filter_none : Icons.crop_square,
        iconSize: _maximized ? 13 : 15,
        tooltip: _maximized ? 'Restore' : 'Maximize',
        onPressed: () => _maximized ? windowManager.unmaximize() : windowManager.maximize(),
      ),
      _CaptionButton(
        icon: Icons.close,
        tooltip: 'Close',
        isClose: true,
        onPressed: windowManager.close,
      ),
    ]);
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
    this.iconSize = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;
  final double iconSize;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    final Color? bg;
    if (widget.isClose && (_hovered || _pressed)) {
      bg = _pressed ? const Color(0xFFC50F1F) : const Color(0xFFE81123);
    } else if (_pressed) {
      bg = c.selectionInactive;
    } else if (_hovered) {
      bg = c.hover;
    } else {
      bg = null;
    }
    final iconColor = widget.isClose && _hovered ? Colors.white : c.icon;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 900),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            setState(() => _pressed = false);
            widget.onPressed();
          },
          child: Container(
            width: 46,
            height: double.infinity,
            color: bg,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
