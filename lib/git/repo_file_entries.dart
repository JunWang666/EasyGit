/// The entries of the repository files the Repo Files tab edits as a list of
/// settings instead of raw text: `.gitignore`, `.gitattributes`, `.lfsconfig`
/// and `.editorconfig`.
///
/// Every entry keeps the line it was read from, so a file the user did not
/// touch is written back byte for byte, comments and spacing included.
library;

/// How a repository file is edited: as entries, or as plain text.
enum RepoFileFormat { ignore, attributes, config, text }

/// The format of the repository file at [path].
RepoFileFormat repoFileFormat(String path) => switch (path.split('/').last.toLowerCase()) {
      '.gitignore' => RepoFileFormat.ignore,
      '.gitattributes' => RepoFileFormat.attributes,
      '.lfsconfig' || '.editorconfig' => RepoFileFormat.config,
      _ => RepoFileFormat.text,
    };

/// The entries of [content] for the file at [path], or null when the file is
/// edited as plain text.
FileEntries? parseFileEntries(String path, String content) =>
    switch (repoFileFormat(path)) {
      RepoFileFormat.ignore => IgnoreEntries.parse(content),
      RepoFileFormat.attributes => AttributeEntries.parse(content),
      RepoFileFormat.config => ConfigEntries.parse(content),
      RepoFileFormat.text => null,
    };

/// The lines of a file plus its line separator and final newline, so written
/// back text matches what was read.
class FileLines {
  const FileLines(this.lines, this.separator, this.finalNewline);

  factory FileLines.parse(String content) {
    if (content.isEmpty) return const FileLines([], '\n', false);
    final separator = content.contains('\r\n') ? '\r\n' : '\n';
    final finalNewline = content.endsWith('\n');
    final body = finalNewline
        ? content.substring(0, content.length - (content.endsWith('\r\n') ? 2 : 1))
        : content;
    return FileLines(
      body.isEmpty
          ? const []
          : [
              for (final line in body.split('\n'))
                line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
            ],
      separator,
      finalNewline,
    );
  }

  final List<String> lines;
  final String separator;
  final bool finalNewline;

  /// Joins [out] the way the file was laid out.
  String join(List<String> out) {
    if (out.isEmpty) return finalNewline ? separator : '';
    return out.join(separator) + (finalNewline ? separator : '');
  }
}

/// One line of a structured file. [raw] is what is written back.
abstract class FileLine {
  const FileLine(this.raw);

  final String raw;
}

/// An empty line, kept so the layout of a file survives an edit.
class BlankLine extends FileLine {
  const BlankLine([super.raw = '']);
}

/// A `#` comment line.
class CommentLine extends FileLine {
  const CommentLine(super.raw);

  /// The comment without its indentation.
  String get text => raw.trim();
}

/// A pattern of a `.gitignore` file, such as `build/` or `!keep.log`.
class IgnoreLine extends FileLine {
  IgnoreLine(this.pattern) : super(pattern);

  /// A rule read from [raw], which keeps its exact text.
  IgnoreLine.fromLine(this.pattern, super.raw);

  final String pattern;

  /// The rule brings a path back (`!`), so it is not ignored.
  bool get negated => pattern.startsWith('!');

  /// The rule covers a whole folder (trailing `/`).
  bool get directory => pattern.endsWith('/');

  /// The path part, without the leading `!` and the trailing `/`.
  String get path =>
      pattern.replaceFirst(RegExp(r'^!'), '').replaceFirst(RegExp(r'/$'), '');
}

/// A pattern with attributes, such as `*.psd filter=lfs -text`.
class AttributeLine extends FileLine {
  AttributeLine(this.pattern, this.attributes)
      : super('$pattern ${attributes.join(' ')}');

  /// A rule read from [raw], which keeps its exact spacing.
  AttributeLine.fromLine(this.pattern, this.attributes, super.raw);

  final String pattern;
  final List<String> attributes;

  /// The path is stored with Git LFS.
  bool get usesLfs => attributes.any((a) => a.startsWith('filter=lfs'));
}

/// A `key = value` entry of a `.lfsconfig` or `.editorconfig` section.
class ConfigPairLine extends FileLine {
  ConfigPairLine(String key, String value, {String indent = ''})
      : key = key,
        value = value,
        indent = indent,
        super('$indent$key = $value');

  /// An entry read from [raw], which keeps its exact spacing.
  ConfigPairLine.fromLine(this.key, this.value, this.indent, super.raw);

  final String key;
  final String value;

  /// The indentation the line had, kept when the entry is edited.
  final String indent;
}

/// A `[section]` header line.
class ConfigSectionLine extends FileLine {
  ConfigSectionLine(this.name) : super('[$name]');

  ConfigSectionLine.fromRaw(super.raw, this.name);

  final String name;
}

/// A `[section]` of a config file and the lines under it.
class ConfigSection {
  ConfigSection(this.header, this.lines);

  /// Null for the lines above the first section.
  final ConfigSectionLine? header;
  final List<FileLine> lines;

  String get name => header?.name ?? '';

  List<ConfigPairLine> get pairs =>
      [for (final line in lines) if (line is ConfigPairLine) line];
}

/// The entries of a repository file that is edited as a list.
sealed class FileEntries {
  /// The content these entries write to the file.
  String toText();
}

/// The patterns and comments of a `.gitignore` file.
final class IgnoreEntries extends FileEntries {
  IgnoreEntries._(this._lines, this.lines);

  factory IgnoreEntries.parse(String content) {
    final lines = FileLines.parse(content);
    return IgnoreEntries._(lines, [
      for (final line in lines.lines)
        if (line.trim().isEmpty)
          BlankLine(line)
        else if (line.trimLeft().startsWith('#'))
          CommentLine(line)
        else
          IgnoreLine.fromLine(line.trim(), line),
    ]);
  }

  final FileLines _lines;
  final List<FileLine> lines;

  List<IgnoreLine> get rules =>
      [for (final line in lines) if (line is IgnoreLine) line];

  int get ruleCount => rules.length;

  /// Adds [pattern]; an empty pattern is ignored.
  void addRule(String pattern) {
    final value = pattern.trim();
    if (value.isEmpty) return;
    lines.add(IgnoreLine(value));
  }

  /// Replaces the rule [line] with one for [pattern].
  void updateRule(FileLine line, String pattern) {
    final value = pattern.trim();
    final index = lines.indexOf(line);
    if (value.isEmpty || index < 0) return;
    lines[index] = IgnoreLine(value);
  }

  void remove(FileLine line) => lines.remove(line);

  @override
  String toText() => _lines.join([for (final line in lines) line.raw]);
}

/// The rules and comments of a `.gitattributes` file.
final class AttributeEntries extends FileEntries {
  AttributeEntries._(this._lines, this.lines);

  factory AttributeEntries.parse(String content) {
    final lines = FileLines.parse(content);
    return AttributeEntries._(lines, [
      for (final line in lines.lines)
        if (line.trim().isEmpty)
          BlankLine(line)
        else if (line.trimLeft().startsWith('#'))
          CommentLine(line)
        else
          _ruleFromLine(line),
    ]);
  }

  static AttributeLine _ruleFromLine(String line) {
    final parts = line.trim().split(RegExp(r'\s+'));
    return AttributeLine.fromLine(parts.first, parts.skip(1).toList(), line);
  }

  final FileLines _lines;
  final List<FileLine> lines;

  List<AttributeLine> get rules =>
      [for (final line in lines) if (line is AttributeLine) line];

  int get ruleCount => rules.length;

  void addRule(String pattern, List<String> attributes) {
    final value = pattern.trim();
    if (value.isEmpty) return;
    lines.add(AttributeLine(value, attributes));
  }

  /// Replaces the rule [line] with new attributes.
  void updateRule(FileLine line, String pattern, List<String> attributes) {
    final value = pattern.trim();
    final index = lines.indexOf(line);
    if (value.isEmpty || index < 0) return;
    lines[index] = AttributeLine(value, attributes);
  }

  void remove(FileLine line) => lines.remove(line);

  @override
  String toText() => _lines.join([for (final line in lines) line.raw]);
}

/// The sections and `key = value` entries of a `.lfsconfig` or
/// `.editorconfig` file.
final class ConfigEntries extends FileEntries {
  ConfigEntries._(this._lines, this.sections);

  factory ConfigEntries.parse(String content) {
    final lines = FileLines.parse(content);
    final sections = <ConfigSection>[ConfigSection(null, [])];
    for (final line in lines.lines) {
      final text = line.trim();
      if (text.length > 2 && text.startsWith('[') && text.endsWith(']')) {
        sections.add(ConfigSection(
            ConfigSectionLine.fromRaw(line, text.substring(1, text.length - 1).trim()),
            []));
      } else if (text.isEmpty) {
        sections.last.lines.add(BlankLine(line));
      } else if (text.startsWith('#') || text.startsWith(';') || !text.contains('=')) {
        // Comments and anything not understood stay exactly as they are.
        sections.last.lines.add(CommentLine(line));
      } else {
        final split = text.indexOf('=');
        sections.last.lines.add(ConfigPairLine.fromLine(
          text.substring(0, split).trim(),
          text.substring(split + 1).trim(),
          line.substring(0, line.length - line.trimLeft().length),
          line,
        ));
      }
    }
    return ConfigEntries._(lines, sections);
  }

  final FileLines _lines;
  final List<ConfigSection> sections;

  int get pairCount =>
      sections.fold(0, (sum, section) => sum + section.pairs.length);

  void addPair(ConfigSection section, String key, String value) {
    final name = key.trim();
    if (name.isEmpty) return;
    final indent = section.pairs.firstOrNull?.indent ?? '';
    section.lines.add(ConfigPairLine(name, value.trim(), indent: indent));
  }

  void updatePair(ConfigSection section, FileLine line, String key, String value) {
    final name = key.trim();
    final index = section.lines.indexOf(line);
    if (name.isEmpty || index < 0) return;
    section.lines[index] = ConfigPairLine(name, value.trim(),
        indent: line is ConfigPairLine ? line.indent : '');
  }

  void removeLine(ConfigSection section, FileLine line) => section.lines.remove(line);

  void addSection(String name) {
    final value = name.trim();
    if (value.isEmpty) return;
    sections.add(ConfigSection(ConfigSectionLine(value), []));
  }

  void renameSection(ConfigSection section, String name) {
    final value = name.trim();
    if (value.isEmpty || section.header == null) return;
    final index = sections.indexOf(section);
    sections[index] = ConfigSection(ConfigSectionLine(value), section.lines);
  }

  void removeSection(ConfigSection section) => sections.remove(section);

  @override
  String toText() => _lines.join([
        for (final section in sections) ...[
          if (section.header != null) section.header!.raw,
          for (final line in section.lines) line.raw,
        ],
      ]);
}
