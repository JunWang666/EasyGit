import 'package:flutter/material.dart';

import '../../theme/ide_theme.dart';
import 'common.dart';

/// Dialog frame in the style of IntelliJ dialogs: title, content, buttons.
class IdeDialog extends StatelessWidget {
  const IdeDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    this.width = 440,
  });

  final String title;
  final Widget content;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return Dialog(
      backgroundColor: c.popupBg,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 14),
              Flexible(child: content),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = 'OK',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => IdeDialog(
      title: title,
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
        IdeButton(label: okLabel, primary: true, onPressed: () => Navigator.pop(context, true)),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String? label,
  String initial = '',
  String okLabel = 'OK',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _InputDialog(title: title, label: label, initial: initial, okLabel: okLabel),
  );
}

class _InputDialog extends StatefulWidget {
  const _InputDialog(
      {required this.title, required this.label, required this.initial, required this.okLabel});

  final String title;
  final String? label;
  final String initial;
  final String okLabel;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return IdeDialog(
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.label != null) ...[Text(widget.label!), const SizedBox(height: 6)],
          IdeTextField(controller: _controller, autofocus: true, onSubmitted: (_) => _submit()),
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: widget.okLabel, primary: true, onPressed: _submit),
      ],
    );
  }
}

/// New branch dialog. Returns the name and whether to check it out.
Future<({String name, bool checkout})?> showNewBranchDialog(
    BuildContext context, String startPoint) {
  return showDialog<({String name, bool checkout})>(
    context: context,
    builder: (context) => _NewBranchDialog(startPoint: startPoint),
  );
}

class _NewBranchDialog extends StatefulWidget {
  const _NewBranchDialog({required this.startPoint});

  final String startPoint;

  @override
  State<_NewBranchDialog> createState() => _NewBranchDialogState();
}

class _NewBranchDialogState extends State<_NewBranchDialog> {
  final _controller = TextEditingController();
  var _checkout = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim().replaceAll(' ', '-');
    if (name.isNotEmpty) Navigator.pop(context, (name: name, checkout: _checkout));
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return IdeDialog(
      title: 'Create New Branch from ${widget.startPoint}',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('New branch name:'),
          const SizedBox(height: 6),
          IdeTextField(controller: _controller, autofocus: true, onSubmitted: (_) => _submit()),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _checkout = !_checkout),
            child: Row(children: [
              Checkbox(
                value: _checkout,
                activeColor: c.accent,
                onChanged: (v) => setState(() => _checkout = v ?? true),
              ),
              const SizedBox(width: 4),
              const Text('Checkout branch'),
            ]),
          ),
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Create', primary: true, onPressed: _submit),
      ],
    );
  }
}

class ChoiceOption<T> {
  const ChoiceOption(this.value, this.label, [this.description]);

  final T value;
  final String label;
  final String? description;
}

/// A dialog with a list of radio-style options.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<ChoiceOption<T>> options,
  required T initial,
  String okLabel = 'OK',
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      var selected = initial;
      final c = IdeColors.of(context);
      return StatefulBuilder(
        builder: (context, setState) => IdeDialog(
          title: title,
          width: 500,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message != null) ...[Text(message), const SizedBox(height: 10)],
              for (final o in options)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => selected = o.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(
                        o.value == selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: o.value == selected ? c.accent : c.buttonBorder,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(o.label),
                          if (o.description != null)
                            Text(o.description!, style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
          actions: [
            IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
            IdeButton(
                label: okLabel, primary: true, onPressed: () => Navigator.pop(context, selected)),
          ],
        ),
      );
    },
  );
}
