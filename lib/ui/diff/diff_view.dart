import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../git/diff.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../widgets/common.dart';
import 'lfs_diff_card.dart';

const _lineHeight = 20.0;
const _gutterWidth = 48.0;

/// Side-by-side or unified diff of one file, shown as an editor tab.
class DiffView extends StatefulWidget {
  const DiffView({super.key, required this.tab});

  final DiffTab tab;

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _PreparedDiff {
  _PreparedDiff(this.content) {
    binary = looksBinary(content.left) || looksBinary(content.right);
    if (binary) return;
    final a = splitLines(content.left ?? '');
    final b = splitLines(content.right ?? '');
    final ops = diffLines(a, b);
    rows = buildSideBySide(a, b, ops);
    unified = buildUnified(a, b, ops);
    rowChanges = changeStarts<DiffRow>(rows, (r) => r.type == DiffRowType.equal);
    unifiedChanges = changeStarts<UnifiedLine>(unified, (l) => l.type == DiffRowType.equal);
    var longest = 0;
    for (final l in a) {
      longest = math.max(longest, l.length);
    }
    for (final l in b) {
      longest = math.max(longest, l.length);
    }
    maxChars = math.min(longest, 1000);
  }

  final DiffContent content;
  late final bool binary;
  List<DiffRow> rows = const [];
  List<UnifiedLine> unified = const [];
  List<int> rowChanges = const [];
  List<int> unifiedChanges = const [];
  int maxChars = 0;
}

class _DiffViewState extends State<DiffView> {
  static var _unifiedMode = false;

  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  Future<_PreparedDiff>? _future;
  String? _loadedId;
  int _loadedVersion = -1;
  int _currentChange = -1;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _ensureLoaded() {
    final tab = widget.tab;
    // The parent keys this widget by tab id, so only the version can change.
    if (_future != null && _loadedId == tab.id && _loadedVersion == tab.version) return;
    _loadedId = tab.id;
    _loadedVersion = tab.version;
    _future = tab.content.then(_PreparedDiff.new);
  }

  void _jump(_PreparedDiff diff, int direction) {
    final changes = _unifiedMode ? diff.unifiedChanges : diff.rowChanges;
    if (changes.isEmpty || !_vertical.hasClients) return;
    setState(() {
      _currentChange = (_currentChange + direction).clamp(0, changes.length - 1);
    });
    final target = changes[_currentChange] * _lineHeight - 3 * _lineHeight;
    _vertical.animateTo(target.clamp(0.0, _vertical.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    _ensureLoaded();
    final c = IdeColors.of(context);
    return FutureBuilder<_PreparedDiff>(
      future: _future,
      builder: (context, snapshot) {
        final diff = snapshot.data;
        final changeCount =
            diff == null ? 0 : (_unifiedMode ? diff.unifiedChanges : diff.rowChanges).length;
        return Container(
          color: c.editorBg,
          child: Column(children: [
            Container(
              height: 34,
              color: c.panelBg,
              child: Row(children: [
                const SizedBox(width: 6),
                IdeIconButton(
                  icon: Icons.arrow_upward,
                  tooltip: 'Previous Difference',
                  onPressed: diff == null ? null : () => _jump(diff, -1),
                ),
                IdeIconButton(
                  icon: Icons.arrow_downward,
                  tooltip: 'Next Difference',
                  onPressed: diff == null ? null : () => _jump(diff, 1),
                ),
                const ToolbarSeparator(),
                _modeButton('Side-by-side', !_unifiedMode, () => setState(() => _unifiedMode = false)),
                _modeButton('Unified', _unifiedMode, () => setState(() => _unifiedMode = true)),
                const ToolbarSeparator(),
                IdeIconButton(
                  icon: Icons.refresh,
                  tooltip: 'Reload',
                  onPressed: () => setState(widget.tab.reload),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.tab.change.path,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(color: c.textSecondary)),
                ),
                if (diff != null && !diff.binary && diff.content.lfs == null)
                  Text(changeCount == 0 ? 'No differences' : '$changeCount difference${changeCount == 1 ? '' : 's'}',
                      style: TextStyle(color: c.textSecondary)),
                const SizedBox(width: 12),
              ]),
            ),
            Container(height: 1, color: c.splitter),
            Expanded(child: _body(snapshot)),
          ]),
        );
      },
    );
  }

  Widget _modeButton(String label, bool active, VoidCallback onTap) {
    final c = IdeColors.of(context);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? c.selectionInactive : (hovered ? c.hover : null),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }

  Widget _body(AsyncSnapshot<_PreparedDiff> snapshot) {
    if (snapshot.hasError) return EmptyHint('Cannot load diff: ${snapshot.error}');
    final diff = snapshot.data;
    if (diff == null) {
      return const Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final lfs = diff.content.lfs;
    if (lfs != null) {
      return LfsDiffCard(
        diff: lfs,
        path: widget.tab.change.path,
        leftTitle: widget.tab.leftTitle,
        rightTitle: widget.tab.rightTitle,
        onChanged: () => setState(widget.tab.reload),
      );
    }
    if (diff.binary) return const EmptyHint('Binary files differ');
    if (diff.content.left == null && diff.content.right == null) {
      return const EmptyHint('File not found');
    }

    final style = monoStyle(context);
    final painter = TextPainter(
        text: TextSpan(text: 'M', style: style), textDirection: TextDirection.ltr)
      ..layout();
    final charWidth = painter.width;
    painter.dispose();

    return LayoutBuilder(builder: (context, constraints) {
      final textWidth = diff.maxChars * charWidth + 24;
      final double contentWidth;
      if (_unifiedMode) {
        contentWidth = math.max(constraints.maxWidth, _gutterWidth * 2 + 20 + textWidth);
      } else {
        // Both columns must stay on screen, so side-by-side never scrolls
        // horizontally; long lines are clipped (Unified scrolls instead).
        contentWidth = constraints.maxWidth;
      }
      final list = _unifiedMode ? _unified(diff, style) : _sideBySide(diff, style);
      return Scrollbar(
        controller: _horizontal,
        notificationPredicate: (n) => n.depth == 0,
        child: SingleChildScrollView(
          controller: _horizontal,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: constraints.maxHeight,
            child: Scrollbar(controller: _vertical, child: list),
          ),
        ),
      );
    });
  }

  Widget _sideBySide(_PreparedDiff diff, TextStyle style) {
    final c = IdeColors.of(context);
    final header = Container(
      height: 24,
      color: c.panelBg,
      child: Row(children: [
        Expanded(child: _headerLabel(widget.tab.leftTitle)),
        Container(width: 1, color: c.splitter),
        Expanded(child: _headerLabel(widget.tab.rightTitle)),
      ]),
    );
    return Column(children: [
      header,
      Expanded(
        child: ListView.builder(
          controller: _vertical,
          itemExtent: _lineHeight,
          itemCount: diff.rows.length,
          itemBuilder: (context, i) {
            final row = diff.rows[i];
            final (leftBg, rightBg) = switch (row.type) {
              DiffRowType.equal => (null, null),
              DiffRowType.changed => (c.diffModified, c.diffModified),
              DiffRowType.deleted => (c.diffDeleted, c.diffFiller),
              DiffRowType.inserted => (c.diffFiller, c.diffInserted),
            };
            return Row(children: [
              Expanded(child: _cell(row.leftNo, row.left, leftBg, style)),
              Container(width: 1, color: c.splitter),
              Expanded(child: _cell(row.rightNo, row.right, rightBg, style)),
            ]);
          },
        ),
      ),
    ]);
  }

  Widget _headerLabel(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: TextStyle(fontSize: 12, color: IdeColors.of(context).textSecondary)),
        ),
      );

  Widget _cell(int? number, String? text, Color? bg, TextStyle style) {
    final c = IdeColors.of(context);
    return Container(
      color: bg,
      child: Row(children: [
        SizedBox(
          width: _gutterWidth,
          child: Text(number?.toString() ?? '',
              textAlign: TextAlign.right,
              style: style.copyWith(color: c.gutterText, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text((text ?? '').replaceAll('\t', '    '),
              maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style),
        ),
      ]),
    );
  }

  Widget _unified(_PreparedDiff diff, TextStyle style) {
    final c = IdeColors.of(context);
    return ListView.builder(
      controller: _vertical,
      itemExtent: _lineHeight,
      itemCount: diff.unified.length,
      itemBuilder: (context, i) {
        final line = diff.unified[i];
        final (bg, prefix) = switch (line.type) {
          DiffRowType.deleted => (c.diffDeleted, '-'),
          DiffRowType.inserted => (c.diffInserted, '+'),
          _ => (null, ' '),
        };
        final gutter = style.copyWith(color: c.gutterText, fontSize: 12);
        return Container(
          color: bg,
          child: Row(children: [
            SizedBox(
                width: _gutterWidth,
                child: Text(line.oldNo?.toString() ?? '', textAlign: TextAlign.right, style: gutter)),
            SizedBox(
                width: _gutterWidth,
                child: Text(line.newNo?.toString() ?? '', textAlign: TextAlign.right, style: gutter)),
            SizedBox(width: 20, child: Text(prefix, textAlign: TextAlign.center, style: gutter)),
            Expanded(
              child: Text(line.text.replaceAll('\t', '    '),
                  maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style),
            ),
          ]),
        );
      },
    );
  }
}
