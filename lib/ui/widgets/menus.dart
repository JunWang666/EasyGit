import 'package:flutter/material.dart';

import '../../theme/ide_theme.dart';

class IdeMenuItem {
  const IdeMenuItem(this.label,
      {this.icon, this.iconColor, this.shortcut, this.onTap, this.enabled = true})
      : isDivider = false;

  const IdeMenuItem.divider()
      : label = '',
        icon = null,
        iconColor = null,
        shortcut = null,
        onTap = null,
        enabled = false,
        isDivider = true;

  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isDivider;
}

/// Shows a compact context menu at [position] (global coordinates).
Future<void> showIdeMenu(
    BuildContext context, Offset position, List<IdeMenuItem> items) async {
  final c = IdeColors.of(context);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final local = overlay.globalToLocal(position);
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
    items: <PopupMenuEntry<int>>[
      for (var i = 0; i < items.length; i++)
        if (items[i].isDivider)
          const PopupMenuDivider(height: 7)
        else
          PopupMenuItem<int>(
            value: i,
            enabled: items[i].enabled && items[i].onTap != null,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 200),
              child: Row(children: [
                SizedBox(
                  width: 22,
                  child: items[i].icon == null
                      ? null
                      : Icon(items[i].icon,
                          size: 15,
                          color: items[i].enabled ? (items[i].iconColor ?? c.icon) : c.textDisabled),
                ),
                Expanded(
                  child: Text(items[i].label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: items[i].enabled ? c.text : c.textDisabled)),
                ),
                if (items[i].shortcut != null) ...[
                  const SizedBox(width: 24),
                  Text(items[i].shortcut!,
                      style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ],
              ]),
            ),
          ),
    ],
  );
  if (selected != null) items[selected].onTap?.call();
}
