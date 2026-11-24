import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../git/models.dart';
import '../../git/repo_file_entries.dart';
import '../../git/repo_files.dart';
import '../../state/repo_controller.dart';
import '../../theme/ide_theme.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/menus.dart';

/// How a template is added to a file that already has content.
enum TemplateApply { replace, append }

/// The repository's own files — `.gitignore`, `.gitattributes`, `.lfsconfig`,
/// `README.md`, `.editorconfig` — with built-in templates, edited in place.
class RepoFilesView extends StatefulWidget {
  const RepoFilesView({super.key, required this.ctrl});

  final RepoController ctrl;

  @override
  State<RepoFilesView> createState() => _RepoFilesViewState();
}

class _RepoFilesViewState extends State<RepoFilesView> {
  RepoController get ctrl => widget.ctrl;

  @override
  void initState() {
    super.initState();
    // After this build: loading notifies the listeners that built this widget.
    Future.microtask(ctrl.loadRepoFiles);
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyS,
            control: !isApplePlatform, meta: isApplePlatform): _save,
      },
      child: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) => Focus(
          autofocus: true,
          child: Container(
            color: c.editorBg,
            child: SplitPane(
              axis: Axis.horizontal,
              initialSize: 300,
              minSize: 200,
              minOther: 360,
              first: Container(color: c.panelBg, child: _fileList()),
              second: _details(),
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final buffer = ctrl.repoFile;
    if (buffer == null) return;
    if (buffer.dirty || !ctrl.repoFileExists(buffer.path)) ctrl.saveRepoFile();
  }

  // ------------------------------------------------------------------- list

  Widget _fileList() {
    final c = IdeColors.of(context);
    return Column(children: [
      PanelHeader(
        title: 'Repository Files',
        trailing: IdeIconButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onPressed: ctrl.loadRepoFiles,
        ),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
          for (final path in ctrl.repoFilePaths) _fileRow(path),
          ListRow(
            height: 34,
            onTap: _newFile,
            child: Row(children: [
              Icon(Icons.add, size: 16, color: c.icon),
              const SizedBox(width: 8),
              Text('New File...', style: TextStyle(color: c.textSecondary)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              'Templates write the file to disk. Commit it from Local Changes.',
              style: TextStyle(fontSize: 11.5, color: c.textSecondary),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _fileRow(String path) {
    final c = IdeColors.of(context);
    final spec = RepoFileSpec.byPath(path);
    final selected = ctrl.repoFile?.path == path;
    return ListRow(
      key: ValueKey('repo-file-$path'),
      height: 42,
      selected: selected,
      onTap: () => ctrl.openRepoFile(path),
      onContextMenu: (position) => _rowMenu(position, path),
      child: Row(children: [
        Icon(_icon(path), size: 16, color: selected ? c.accent : c.icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 12.5)),
              Text(spec?.summary ?? 'Added by hand',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _badge(path),
      ]),
    );
  }

  Widget _badge(String path) {
    final buffer = ctrl.repoFile?.path == path ? ctrl.repoFile : null;
    // Typing in a plain-text file only notifies its own controller.
    if (buffer == null || buffer.entries != null) return _badgeBody(path);
    return ListenableBuilder(
      listenable: buffer.controller,
      builder: (context, _) => _badgeBody(path),
    );
  }

  Widget _badgeBody(String path) {
    final c = IdeColors.of(context);
    if (ctrl.repoFileDirty(path)) {
      return Tooltip(
        message: 'Unsaved changes',
        child: Icon(Icons.circle, size: 8, color: c.accent),
      );
    }
    if (!ctrl.repoFilesLoaded) return const SizedBox.shrink();
    final change = _changeFor(path);
    if (change != null) {
      final color = c.statusColor(change.kind);
      return Tooltip(
        message: 'Changed locally',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              color: color.withAlpha(50), borderRadius: BorderRadius.circular(8)),
          child: Text(_kindLetter(change.kind),
              style: TextStyle(fontSize: 11, color: color)),
        ),
      );
    }
    if (!ctrl.repoFileExists(path)) {
      return Tooltip(
        message: 'This file is not in the repository yet',
        child: Text('new', style: TextStyle(fontSize: 11, color: c.textDisabled)),
      );
    }
    return const SizedBox.shrink();
  }

  void _rowMenu(Offset position, String path) {
    final exists = ctrl.repoFileExists(path);
    showIdeMenu(context, position, [
      IdeMenuItem('Open',
          icon: Icons.edit_outlined, onTap: () => ctrl.openRepoFile(path)),
      if (exists)
        IdeMenuItem('Delete...',
            icon: Icons.delete_outline, onTap: () => _delete(path)),
      if (ctrl.extraRepoFiles.contains(path)) ...[
        const IdeMenuItem.divider(),
        IdeMenuItem('Remove from List',
            icon: Icons.close, onTap: () => ctrl.forgetRepoFile(path)),
      ],
    ]);
  }

  Future<void> _newFile() async {
    final input = await showInputDialog(context,
        title: 'New File',
        label: 'Path inside the repository:',
        okLabel: 'Open');
    if (input == null) return;
    final path = normalizeRepoFilePath(input);
    if (path == null) {
      ctrl.reportError('New File',
          'Enter a path inside the repository, such as docs/NOTES.md.');
      return;
    }
    await ctrl.addRepoFile(path);
  }

  Future<void> _delete(String path) async {
    final ok = await showConfirmDialog(context,
        title: 'Delete File',
        message: '$path is deleted from the working tree.\n\n'
            'If Git tracks it, the deletion appears in Local Changes and can be committed.',
        okLabel: 'Delete');
    if (ok) await ctrl.deleteRepoFile(path);
  }

  // ---------------------------------------------------------------- details

  Widget _details() {
    final c = IdeColors.of(context);
    final buffer = ctrl.repoFile;
    if (buffer == null) {
      return Container(
        color: c.editorBg,
        child: const EmptyHint(
            'Select a file to edit it. A file that does not exist yet can be '
            'created from a template.'),
      );
    }
    return ListenableBuilder(
      listenable: buffer.controller,
      builder: (context, _) => Column(children: [
        _detailsHeader(buffer),
        Container(height: 1, color: c.border),
        Expanded(child: _detailsBody(buffer)),
      ]),
    );
  }

  Widget _detailsHeader(RepoFileBuffer buffer) {
    final c = IdeColors.of(context);
    final exists = ctrl.repoFileExists(buffer.path);
    final spec = RepoFileSpec.byPath(buffer.path);
    final canSave = buffer.dirty || !exists;
    return Container(
      height: 46,
      color: c.panelBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(_icon(buffer.path), size: 18, color: c.icon),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(buffer.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(context, size: 13)),
              Text(_statusLine(buffer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
            ],
          ),
        ),
        if (exists && spec != null)
          Builder(
            builder: (context) => IdeButton(
              label: 'Templates...',
              onPressed: () => _templatesMenu(context, spec),
            ),
          ),
        if (exists) ...[
          const SizedBox(width: 6),
          IdeIconButton(
            icon: Icons.undo,
            tooltip: 'Reload from Disk',
            onPressed: ctrl.reloadRepoFile,
          ),
          IdeIconButton(
            icon: Icons.delete_outline,
            tooltip: 'Delete ${buffer.path}',
            onPressed: () => _delete(buffer.path),
          ),
        ],
        const SizedBox(width: 6),
        IdeButton(
          label: exists ? 'Save' : 'Create',
          primary: true,
          onPressed: canSave ? ctrl.saveRepoFile : null,
        ),
      ]),
    );
  }

  String _statusLine(RepoFileBuffer buffer) {
    if (ctrl.repoFileLoading) return 'Loading...';
    if (!ctrl.repoFileExists(buffer.path)) return 'Not created yet';
    if (buffer.dirty) return 'Unsaved changes, ${shortcutLabel('S')} to save';
    final summary = switch (buffer.entries) {
      IgnoreEntries(:final ruleCount) =>
        '$ruleCount pattern${ruleCount == 1 ? '' : 's'}',
      AttributeEntries(:final ruleCount) =>
        '$ruleCount attribute rule${ruleCount == 1 ? '' : 's'}',
      ConfigEntries(:final pairCount) =>
        '$pairCount setting${pairCount == 1 ? '' : 's'}',
      null => 'Plain text',
    };
    if (_changeFor(buffer.path) != null) {
      return '$summary, changed in the working tree';
    }
    return summary;
  }

  Widget _detailsBody(RepoFileBuffer buffer) {
    if (!ctrl.repoFilesLoaded || ctrl.repoFileLoading) {
      return const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (!ctrl.repoFileExists(buffer.path)) return _gallery(buffer);
    final entries = buffer.entries;
    if (entries == null) return _textEditor(buffer);
    return switch (entries) {
      IgnoreEntries() => _ignoreEditor(entries),
      AttributeEntries() => _attributesEditor(entries),
      ConfigEntries() => _configEditor(entries),
    };
  }

  /// A file without a known structure: README, or one added by hand.
  Widget _textEditor(RepoFileBuffer buffer) {
    final c = IdeColors.of(context);
    return Container(
      color: c.editorBg,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: TextField(
        key: ValueKey('repo-file-editor-${buffer.path}'),
        controller: buffer.controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: monoStyle(context, size: 13),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- entries

  /// `.gitignore`: one row per pattern, with comments kept in place.
  Widget _ignoreEditor(IgnoreEntries entries) {
    final visible = [for (final line in entries.lines) if (line is! BlankLine) line];
    return Column(children: [
      Expanded(
        child: visible.isEmpty
            ? const EmptyHint(
                'No patterns yet. Add one below, or insert a template.')
            : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                for (final line in visible)
                  switch (line) {
                    IgnoreLine() => _ignoreRow(entries, line),
                    CommentLine() => _commentRow(
                        line.text,
                        () => ctrl.updateRepoFile(() => entries.remove(line))),
                    _ => const SizedBox.shrink(),
                  },
              ]),
      ),
      _AddField(
        key: ValueKey('add-pattern-${ctrl.repoFile?.path}'),
        hint: 'Pattern to ignore: *.log, build/ or !keep.log',
        label: 'Add Pattern',
        onAdd: (value) => ctrl.updateRepoFile(() => entries.addRule(value)),
      ),
    ]);
  }

  Widget _ignoreRow(IgnoreEntries entries, IgnoreLine line) {
    final c = IdeColors.of(context);
    return ListRow(
      height: 32,
      onTap: () => _editIgnoreRule(entries, line),
      child: Row(children: [
        Icon(
          line.negated
              ? Icons.visibility_outlined
              : line.directory
                  ? Icons.folder_outlined
                  : Icons.visibility_off_outlined,
          size: 15,
          color: line.negated ? c.success : c.icon,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(line.pattern,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12.5)),
        ),
        if (line.negated) _tag('kept', c.success),
        if (line.directory) _tag('folder', c.textSecondary),
        const SizedBox(width: 4),
        _removeButton('Remove ${line.pattern}',
            () => ctrl.updateRepoFile(() => entries.remove(line))),
      ]),
    );
  }

  Future<void> _editIgnoreRule(IgnoreEntries entries, IgnoreLine line) async {
    final value = await showInputDialog(context,
        title: 'Ignore Pattern',
        label: 'Pattern (start with ! to keep a path):',
        initial: line.pattern,
        okLabel: 'Save');
    if (value == null) return;
    ctrl.updateRepoFile(() => entries.updateRule(line, value));
  }

  /// `.gitattributes`: one row per pattern, with its attributes beside it.
  Widget _attributesEditor(AttributeEntries entries) {
    final visible = [for (final line in entries.lines) if (line is! BlankLine) line];
    return Column(children: [
      Expanded(
        child: visible.isEmpty
            ? const EmptyHint('No attribute rules yet. Add one below.')
            : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                for (final line in visible)
                  switch (line) {
                    AttributeLine() => _attributeRow(entries, line),
                    CommentLine() => _commentRow(
                        line.text,
                        () => ctrl.updateRepoFile(() => entries.remove(line))),
                    _ => const SizedBox.shrink(),
                  },
              ]),
      ),
      _actionBar([
        IdeButton(
            label: 'Add Rule...',
            primary: true,
            onPressed: () => _editAttributeRule(entries)),
      ]),
    ]);
  }

  Widget _attributeRow(AttributeEntries entries, AttributeLine line) {
    final c = IdeColors.of(context);
    return ListRow(
      height: 34,
      onTap: () => _editAttributeRule(entries, line),
      child: Row(children: [
        Icon(Icons.tune, size: 15, color: c.icon),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(line.pattern,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12.5)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Row(children: [
            if (line.usesLfs) ...[_tag('LFS', c.accent), const SizedBox(width: 6)],
            Expanded(
              child: Text(
                line.attributes.isEmpty
                    ? '(no attributes)'
                    : line.attributes.join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, size: 11.5, color: c.textSecondary),
              ),
            ),
          ]),
        ),
        _removeButton('Remove ${line.pattern}',
            () => ctrl.updateRepoFile(() => entries.remove(line))),
      ]),
    );
  }

  Future<void> _editAttributeRule(AttributeEntries entries,
      [AttributeLine? line]) async {
    final result = await showDialog<({String pattern, List<String> attributes})>(
      context: context,
      builder: (context) => _AttributeRuleDialog(
        pattern: line?.pattern ?? '',
        attributes: line?.attributes.join(' ') ?? '',
      ),
    );
    if (result == null) return;
    ctrl.updateRepoFile(() => line == null
        ? entries.addRule(result.pattern, result.attributes)
        : entries.updateRule(line, result.pattern, result.attributes));
  }

  /// `.lfsconfig` and `.editorconfig`: sections with key/value entries.
  Widget _configEditor(ConfigEntries entries) {
    final sections = [
      for (final section in entries.sections)
        if (section.header != null ||
            section.lines.any((line) => line is! BlankLine))
          section,
    ];
    return Column(children: [
      Expanded(
        child: sections.isEmpty
            ? const EmptyHint('No settings yet. Add a section and an entry.')
            : ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: [
                for (final section in sections) ...[
                  _sectionRow(entries, section),
                  for (final line in section.lines)
                    switch (line) {
                      ConfigPairLine() => _pairRow(entries, section, line),
                      CommentLine() => _commentRow(
                          line.text,
                          () => ctrl.updateRepoFile(
                              () => entries.removeLine(section, line))),
                      _ => const SizedBox.shrink(),
                    },
                ],
              ]),
      ),
      _actionBar([
        IdeButton(
            label: 'Add Section...',
            onPressed: () => _addSection(entries)),
      ]),
    ]);
  }

  Widget _sectionRow(ConfigEntries entries, ConfigSection section) {
    final c = IdeColors.of(context);
    final header = section.header;
    return ListRow(
      height: 34,
      onTap: header == null ? null : () => _renameSection(entries, section),
      child: Row(children: [
        Icon(header == null ? Icons.subject : Icons.folder_open_outlined,
            size: 15, color: c.textSecondary),
        const SizedBox(width: 8),
        Text(
          header == null ? 'General' : '[${section.name}]',
          style: header == null
              ? TextStyle(fontSize: 12.5, color: c.textSecondary)
              : monoStyle(context, size: 12.5),
        ),
        const Spacer(),
        IdeIconButton(
          icon: Icons.add,
          tooltip: 'Add Entry to ${header == null ? 'General' : '[${section.name}]'}',
          size: 24,
          iconSize: 14,
          onPressed: () => _editPair(entries, section),
        ),
        if (header != null)
          _removeButton('Remove [${section.name}]',
              () => ctrl.updateRepoFile(() => entries.removeSection(section)))
        else
          const SizedBox(width: 24),
      ]),
    );
  }

  Widget _pairRow(ConfigEntries entries, ConfigSection section, ConfigPairLine line) {
    final c = IdeColors.of(context);
    return ListRow(
      height: 32,
      onTap: () => _editPair(entries, section, line),
      child: Row(children: [
        SizedBox(
          width: 190,
          child: Text(line.key,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12, color: c.textSecondary)),
        ),
        Text('=', style: TextStyle(color: c.textDisabled)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(line.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(context, size: 12.5)),
        ),
        _removeButton('Remove ${line.key}',
            () => ctrl.updateRepoFile(() => entries.removeLine(section, line))),
      ]),
    );
  }

  Future<void> _editPair(ConfigEntries entries, ConfigSection section,
      [ConfigPairLine? line]) async {
    final result = await showDialog<({String key, String value})>(
      context: context,
      builder: (context) => _PairDialog(
          initialKey: line?.key ?? '',
          initialValue: line?.value ?? '',
          isNew: line == null),
    );
    if (result == null) return;
    ctrl.updateRepoFile(() => line == null
        ? entries.addPair(section, result.key, result.value)
        : entries.updatePair(section, line, result.key, result.value));
  }

  Future<void> _addSection(ConfigEntries entries) async {
    final name = await showInputDialog(context,
        title: 'Add Section',
        label: 'Section name:',
        initial: '*',
        okLabel: 'Add');
    if (name == null) return;
    ctrl.updateRepoFile(() => entries.addSection(name));
  }

  Future<void> _renameSection(ConfigEntries entries, ConfigSection section) async {
    final name = await showInputDialog(context,
        title: 'Rename Section',
        label: 'Section name:',
        initial: section.name,
        okLabel: 'Rename');
    if (name == null) return;
    ctrl.updateRepoFile(() => entries.renameSection(section, name));
  }

  Widget _commentRow(String text, VoidCallback onRemove) {
    final c = IdeColors.of(context);
    return ListRow(
      height: 28,
      child: Row(children: [
        Icon(Icons.notes, size: 14, color: c.textDisabled),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: c.textSecondary)),
        ),
        _removeButton('Remove comment', onRemove),
      ]),
    );
  }

  Widget _tag(String label, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
            color: color.withAlpha(40), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(fontSize: 10, color: color)),
      );

  Widget _removeButton(String tooltip, VoidCallback onPressed) => IdeIconButton(
        icon: Icons.close,
        tooltip: tooltip,
        size: 24,
        iconSize: 14,
        onPressed: onPressed,
      );

  /// The strip of buttons under a list of entries.
  Widget _actionBar(List<Widget> actions) {
    final c = IdeColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: c.panelBg,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(children: actions),
    );
  }

  /// Shown for a file that does not exist yet: start from a template.
  Widget _gallery(RepoFileBuffer buffer) {
    final c = IdeColors.of(context);
    final spec = RepoFileSpec.byPath(buffer.path);
    final templates = spec?.templates ?? const <FileTemplate>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${buffer.path} is not in the working tree yet',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          spec?.summary ?? 'Create it empty and write the content yourself.',
          style: TextStyle(color: c.textSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final template in templates)
            _TemplateCard(
              name: template.name,
              description: template.description,
              preview: _previewOf(template, lines: 3),
              recommended: template.isRecommended(ctrl.repoRootEntries),
              onTap: () => ctrl.applyRepoFileTemplate(template, append: false),
            ),
          _TemplateCard(
            name: 'Empty file',
            description: 'Start with no content and write the file yourself.',
            preview: '',
            onTap: ctrl.saveRepoFile,
          ),
        ]),
      ]),
    );
  }

  String _previewOf(FileTemplate template, {int lines = 12}) => template
      .render(ctrl.templateValues())
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(lines)
      .join('\n');

  // -------------------------------------------------------------- templates

  void _templatesMenu(BuildContext anchor, RepoFileSpec spec) {
    final box = anchor.findRenderObject()! as RenderBox;
    showIdeMenu(context, box.localToGlobal(Offset(0, box.size.height)), [
      for (final template in spec.templates)
        IdeMenuItem(template.name,
            icon: Icons.description_outlined,
            onTap: () => _applyTemplate(template)),
    ]);
  }

  Future<void> _applyTemplate(FileTemplate template) async {
    final buffer = ctrl.repoFile;
    if (buffer == null) return;
    var append = false;
    if (buffer.text.trim().isNotEmpty) {
      final mode = await _askApplyMode(template);
      if (mode == null) return;
      append = mode == TemplateApply.append;
    }
    await ctrl.applyRepoFileTemplate(template, append: append);
  }

  Future<TemplateApply?> _askApplyMode(FileTemplate template) =>
      showDialog<TemplateApply>(
        context: context,
        builder: (context) {
          final c = IdeColors.of(context);
          return IdeDialog(
            title: 'Add Template: ${template.name}',
            width: 560,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(template.description),
                const SizedBox(height: 10),
                Container(
                  height: 150,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.editorBg,
                    border: Border.all(color: c.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: SingleChildScrollView(
                    child: Text(_previewOf(template, lines: 40),
                        style: monoStyle(context, size: 11.5)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Append keeps the current content and adds the template after a '
                  'blank line. Replace drops the current content.',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
            actions: [
              IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
              IdeButton(
                  label: 'Append',
                  onPressed: () => Navigator.pop(context, TemplateApply.append)),
              IdeButton(
                  label: 'Replace',
                  primary: true,
                  onPressed: () => Navigator.pop(context, TemplateApply.replace)),
            ],
          );
        },
      );

  // ----------------------------------------------------------------- lookups

  FileChange? _changeFor(String path) =>
      ctrl.status?.changes.where((c) => c.path == path).firstOrNull;

  static IconData _icon(String path) => switch (path) {
        '.gitignore' => Icons.visibility_off_outlined,
        '.gitattributes' => Icons.tune,
        '.lfsconfig' => Icons.cloud_outlined,
        '.editorconfig' => Icons.format_align_left,
        _ => fileIcon(path.split('/').last),
      };

  static String _kindLetter(ChangeKind kind) => switch (kind) {
        ChangeKind.modified => 'M',
        ChangeKind.added => 'A',
        ChangeKind.deleted => 'D',
        ChangeKind.renamed => 'R',
        ChangeKind.copied => 'C',
        ChangeKind.typeChanged => 'T',
        ChangeKind.untracked => 'U',
        ChangeKind.conflicted => '!',
      };
}

/// A clickable card of the template gallery.
class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.name,
    required this.description,
    required this.preview,
    required this.onTap,
    this.recommended = false,
  });

  final String name;
  final String description;
  final String preview;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 258,
          height: 148,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: hovered ? c.hover : c.editorBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: hovered ? c.accent : c.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (recommended) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: c.accent.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Recommended',
                      style: TextStyle(fontSize: 10.5, color: c.accent)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.textSecondary)),
            const Spacer(),
            if (preview.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: c.panelBg, borderRadius: BorderRadius.circular(4)),
                child: Text(preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(context, size: 10.5, color: c.textSecondary)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The "add an entry" strip under a list of patterns.
class _AddField extends StatefulWidget {
  const _AddField(
      {super.key, required this.hint, required this.label, required this.onAdd});

  final String hint;
  final String label;
  final ValueChanged<String> onAdd;

  @override
  State<_AddField> createState() => _AddFieldState();
}

class _AddFieldState extends State<_AddField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onAdd(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: BoxDecoration(
        color: c.panelBg,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(children: [
        Expanded(
          child: IdeTextField(
            controller: _controller,
            hint: widget.hint,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 8),
        IdeButton(label: widget.label, primary: true, onPressed: _submit),
      ]),
    );
  }
}

/// Adds or edits a rule of a `.gitattributes` file.
class _AttributeRuleDialog extends StatefulWidget {
  const _AttributeRuleDialog({required this.pattern, required this.attributes});

  final String pattern;
  final String attributes;

  @override
  State<_AttributeRuleDialog> createState() => _AttributeRuleDialogState();
}

class _AttributeRuleDialogState extends State<_AttributeRuleDialog> {
  late final _pattern = TextEditingController(text: widget.pattern);
  late final _attributes = TextEditingController(text: widget.attributes);

  @override
  void dispose() {
    _pattern.dispose();
    _attributes.dispose();
    super.dispose();
  }

  void _submit() {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) return;
    Navigator.pop(context, (
      pattern: pattern,
      attributes: _attributes.text
          .split(RegExp(r'\s+'))
          .where((part) => part.isNotEmpty)
          .toList(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = IdeColors.of(context);
    return IdeDialog(
      title: widget.pattern.isEmpty ? 'Add Attribute Rule' : 'Attribute Rule',
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pattern:'),
          const SizedBox(height: 6),
          IdeTextField(
            controller: _pattern,
            hint: 'e.g. *.psd or docs/**',
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          const Text('Attributes:'),
          const SizedBox(height: 6),
          IdeTextField(
            controller: _attributes,
            hint: 'e.g. filter=lfs diff=lfs merge=lfs -text',
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Separate attributes with spaces. "-text" turns off text handling; '
            '"binary" is short for -diff -merge -text.',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Save', primary: true, onPressed: _submit),
      ],
    );
  }
}

/// Adds or edits a `key = value` entry of a config file.
class _PairDialog extends StatefulWidget {
  const _PairDialog(
      {required this.initialKey, required this.initialValue, this.isNew = false});

  final String initialKey;
  final String initialValue;
  final bool isNew;

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  late final _key = TextEditingController(text: widget.initialKey);
  late final _value = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    final key = _key.text.trim();
    if (key.isEmpty) return;
    Navigator.pop(context, (key: key, value: _value.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return IdeDialog(
      title: widget.isNew ? 'Add Entry' : 'Edit Entry',
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Key:'),
          const SizedBox(height: 6),
          IdeTextField(
            controller: _key,
            hint: 'e.g. url, fetchexclude, indent_size',
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          const Text('Value:'),
          const SizedBox(height: 6),
          IdeTextField(
            controller: _value,
            hint: 'e.g. https://lfs.example.com/team/app',
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        IdeButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        IdeButton(label: 'Save', primary: true, onPressed: _submit),
      ],
    );
  }
}
