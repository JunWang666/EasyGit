/// Repository files EasyGit can create and edit: `.gitignore`, `.gitattributes`,
/// `.lfsconfig`, `README.md` and `.editorconfig`, with their built-in templates.
///
/// The templates are plain text. `{{name}}` placeholders are replaced by
/// [FileTemplate.render] before the text reaches the repository, so a template
/// can mention the project name or the LFS server of the repository.
library;

/// One built-in snippet that can create a file or be appended to it.
class FileTemplate {
  const FileTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.content,
    this.recommendedWhen = const [],
  });

  /// Stable id, unique inside its file.
  final String id;

  /// Short name shown in menus and template cards.
  final String name;

  /// One sentence about what the template does.
  final String description;

  /// The text to insert, with `{{name}}` placeholders.
  final String content;

  /// Repository root entries that make this template a good fit: a file name,
  /// a folder name, or a `*.ext` pattern.
  final List<String> recommendedWhen;

  /// Whether the repository root (file and folder names) suggests this template.
  bool isRecommended(Set<String> rootEntries) => recommendedWhen.any(
        (marker) => marker.startsWith('*.')
            ? rootEntries.any((entry) => entry.endsWith(marker.substring(1)))
            : rootEntries.contains(marker),
      );

  /// [content] with every `{{name}}` placeholder taken from [values].
  String render([Map<String, String> values = const {}]) => content
      .replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (match) => values[match[1]] ?? '');
}

/// A file in the repository root that EasyGit offers to create or edit.
class RepoFileSpec {
  const RepoFileSpec({
    required this.path,
    required this.summary,
    required this.templates,
  });

  /// Path relative to the repository root, always with `/` separators.
  final String path;

  /// What the file is for, shown under its name.
  final String summary;

  final List<FileTemplate> templates;

  static RepoFileSpec? byPath(String path) =>
      repoFileSpecs.where((spec) => spec.path == path).firstOrNull;

  /// The first template that fits the repository's root entries, if any.
  FileTemplate? recommendedTemplate(Set<String> rootEntries) =>
      templates.where((template) => template.isRecommended(rootEntries)).firstOrNull;
}

/// The files the Repo Files tab manages, in the order it lists them.
const List<RepoFileSpec> repoFileSpecs = [
  RepoFileSpec(
    path: '.gitignore',
    summary: 'Files and folders Git should leave out',
    templates: [
      FileTemplate(
        id: 'dart',
        name: 'Dart / Flutter',
        description: 'Build output, package caches and the IDE files of a Dart or '
            'Flutter project.',
        recommendedWhen: ['pubspec.yaml'],
        content: r'''# Dart and Flutter
.dart_tool/
.pub-cache/
.pub/
.packages
build/
coverage/
.flutter-plugins
.flutter-plugins-dependencies
doc/api/
*.iml

# Flutter app build output
android/.gradle/
android/local.properties
android/app/debug/
android/app/profile/
android/app/release/
ios/Flutter/Generated.xcconfig
ios/Flutter/flutter_export_environment.sh
''',
      ),
      FileTemplate(
        id: 'node',
        name: 'Node.js',
        description: 'node_modules, package manager caches, build folders and logs.',
        recommendedWhen: ['package.json'],
        content: r'''# Node.js
node_modules/
.npm/
.pnpm-store/
.yarn/
dist/
build/
coverage/
*.tsbuildinfo

npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
''',
      ),
      FileTemplate(
        id: 'python',
        name: 'Python',
        description: 'Byte code, virtual environments, test and type checker caches.',
        recommendedWhen: [
          'pyproject.toml',
          'requirements.txt',
          'setup.py',
          'setup.cfg',
          'Pipfile',
        ],
        content: r'''# Python
__pycache__/
*.py[cod]
*.egg-info/
.eggs/
build/
dist/
.venv/
venv/
.mypy_cache/
.pytest_cache/
.ruff_cache/
.coverage
htmlcov/
.ipynb_checkpoints/
''',
      ),
      FileTemplate(
        id: 'java',
        name: 'Java / Gradle / Maven',
        description: 'Compiled classes, target folders and the Gradle cache, but not '
            'the wrapper jar.',
        recommendedWhen: [
          'pom.xml',
          'build.gradle',
          'build.gradle.kts',
          'settings.gradle',
          'settings.gradle.kts',
        ],
        content: r'''# Java, Gradle and Maven
*.class
target/
out/
bin/
.gradle/
!gradle/wrapper/gradle-wrapper.jar
*.jar
*.war
hs_err_pid*
''',
      ),
      FileTemplate(
        id: 'dotnet',
        name: 'C# / .NET',
        description: 'bin and obj folders, Visual Studio state and NuGet packages.',
        recommendedWhen: ['*.sln', '*.csproj'],
        content: r'''# .NET, C# and Visual Studio
bin/
obj/
.vs/
*.user
*.suo
*.userprefs
*.sln.docstates
TestResults/
packages/
*.nupkg
''',
      ),
      FileTemplate(
        id: 'go',
        name: 'Go',
        description: 'Compiled binaries and test output.',
        recommendedWhen: ['go.mod'],
        content: r'''# Go
/bin/
*.exe
*.exe~
*.dll
*.so
*.dylib
*.test
*.out
''',
      ),
      FileTemplate(
        id: 'rust',
        name: 'Rust',
        description: 'The Cargo target folder and backup files.',
        recommendedWhen: ['Cargo.toml'],
        content: r'''# Rust
/target/
**/*.rs.bk
''',
      ),
      FileTemplate(
        id: 'xcode',
        name: 'Xcode',
        description: 'Derived data, per-user project state and archives.',
        recommendedWhen: ['*.xcodeproj', '*.xcworkspace', 'Podfile'],
        content: r'''# Xcode
build/
DerivedData/
xcuserdata/
*.xcuserstate
*.xcscmblueprint
*.xccheckout
*.moved-aside
*.hmap
*.ipa
*.dSYM.zip
''',
      ),
      FileTemplate(
        id: 'jetbrains',
        name: 'JetBrains IDEs',
        description: 'The .idea folder and module files of IntelliJ IDEA, GoLand, '
            'WebStorm and friends.',
        recommendedWhen: ['.idea'],
        content: r'''# JetBrains IDEs
.idea/
*.iml
*.ipr
*.iws
out/
''',
      ),
      FileTemplate(
        id: 'vscode',
        name: 'Visual Studio Code',
        description: 'Workspace settings, but keeps launch, task and extension '
            'recommendations.',
        recommendedWhen: ['.vscode'],
        content: r'''# Visual Studio Code
.vscode/*
!.vscode/extensions.json
!.vscode/launch.json
!.vscode/settings.json
!.vscode/tasks.json
*.code-workspace
''',
      ),
      FileTemplate(
        id: 'os',
        name: 'macOS / Windows / Linux',
        description: 'The usual junk files of the three desktop systems.',
        content: r'''# macOS
.DS_Store
.AppleDouble
.LSOverride
._*

# Windows
Thumbs.db
ehthumbs.db
Desktop.ini
$RECYCLE.BIN/
*.lnk

# Linux
*~
.directory
''',
      ),
      FileTemplate(
        id: 'secrets',
        name: 'Secrets and .env',
        description: 'Local environment files, keys and certificates. Keeps '
            '.env.example.',
        recommendedWhen: ['.env'],
        content: r'''# Local secrets and environment files
.env
.env.*
!.env.example
*.pem
*.key
*.p12
*.pfx
*.keystore
secrets.properties
''',
      ),
    ],
  ),
  RepoFileSpec(
    path: '.gitattributes',
    summary: 'Line endings, LFS and diff rules per path',
    templates: [
      FileTemplate(
        id: 'text',
        name: 'Line endings',
        description: 'Stores LF in the repository and checks out CRLF for Windows '
            'scripts and project files.',
        content: r'''# Line endings: LF in the repository, CRLF where a Windows tool needs it.
* text=auto

*.dart text eol=lf
*.sh text eol=lf
*.md text eol=lf
*.json text eol=lf
*.yaml text eol=lf
*.yml text eol=lf

*.bat text eol=crlf
*.cmd text eol=crlf
*.ps1 text eol=crlf
*.sln text eol=crlf
*.csproj text eol=crlf
''',
      ),
      FileTemplate(
        id: 'lfs',
        name: 'Git LFS for large files',
        description: 'Routes design files, media, archives and Office documents '
            'through Git LFS.',
        recommendedWhen: ['*.psd', '*.blend', '*.fbx', '*.mp4'],
        content: r'''# Large binary files are stored with Git LFS.
# Everyone who clones needs git-lfs; run "git lfs install" once per computer.
*.psd    filter=lfs diff=lfs merge=lfs -text
*.psb    filter=lfs diff=lfs merge=lfs -text
*.ai     filter=lfs diff=lfs merge=lfs -text
*.sketch filter=lfs diff=lfs merge=lfs -text
*.blend  filter=lfs diff=lfs merge=lfs -text
*.fbx    filter=lfs diff=lfs merge=lfs -text
*.obj    filter=lfs diff=lfs merge=lfs -text
*.mp4    filter=lfs diff=lfs merge=lfs -text
*.mov    filter=lfs diff=lfs merge=lfs -text
*.wav    filter=lfs diff=lfs merge=lfs -text
*.flac   filter=lfs diff=lfs merge=lfs -text
*.zip    filter=lfs diff=lfs merge=lfs -text
*.7z     filter=lfs diff=lfs merge=lfs -text
*.ttf    filter=lfs diff=lfs merge=lfs -text
*.otf    filter=lfs diff=lfs merge=lfs -text
*.docx   filter=lfs diff=lfs merge=lfs -text
*.xlsx   filter=lfs diff=lfs merge=lfs -text
*.pptx   filter=lfs diff=lfs merge=lfs -text
''',
      ),
      FileTemplate(
        id: 'linguist',
        name: 'Language statistics',
        description: 'Keeps generated files, lock files and vendored code out of the '
            'language bar on GitHub and GitLab.',
        content: r'''# What the hosting site counts as this project's languages.
*.min.js linguist-generated=true
*.min.css linguist-generated=true
package-lock.json linguist-generated=true -diff
pnpm-lock.yaml linguist-generated=true -diff
yarn.lock linguist-generated=true -diff
vendor/** linguist-vendored
third_party/** linguist-vendored
docs/** linguist-documentation
''',
      ),
      FileTemplate(
        id: 'binary',
        name: 'Binary formats',
        description: 'Marks common binary formats as binary: no text diff and no '
            'line-ending conversion.',
        content: r'''# Binary formats: no text diff, no line-ending conversion.
*.png binary
*.jpg binary
*.jpeg binary
*.gif binary
*.ico binary
*.pdf binary
*.zip binary
*.7z binary
*.gz binary
*.exe binary
*.dll binary
*.so binary
*.dylib binary
*.woff binary
*.woff2 binary
''',
      ),
    ],
  ),
  RepoFileSpec(
    path: '.lfsconfig',
    summary: 'LFS server and download rules',
    templates: [
      FileTemplate(
        id: 'shared',
        name: 'Shared LFS server',
        description: 'Pins the LFS server for everyone who clones, instead of '
            'deriving it from the remote.',
        content: r'''# The LFS server everyone who clones this repository uses.
# Precedence: local "git config lfs.url" > this file > derived from the remote.
[lfs]
	url = {{lfsUrl}}
''',
      ),
      FileTemplate(
        id: 'fetchexclude',
        name: 'Skip big files on download',
        description: 'Leaves these paths as pointers until someone asks for them with '
            '"git lfs pull".',
        content: r'''# Paths that "git lfs pull" and clone leave out unless they are requested.
# Comma separated, .gitignore syntax.
[lfs]
	fetchexclude = *.zip,*.7z,*.mp4
''',
      ),
      FileTemplate(
        id: 'locks',
        name: 'Verify file locks',
        description: 'Asks the server about locked files before a push, so a locked '
            'file is not overwritten.',
        content: r'''# Check file locks with the server before pushing.
[lfs]
	locksverify = true
''',
      ),
    ],
  ),
  RepoFileSpec(
    path: 'README.md',
    summary: 'What the project is and how to use it',
    templates: [
      FileTemplate(
        id: 'minimal',
        name: 'Minimal',
        description: 'A title and one sentence, for a project that speaks for '
            'itself.',
        content: r'''# {{project}}

A short description of what this project does.
''',
      ),
      FileTemplate(
        id: 'standard',
        name: 'Standard project',
        description: 'Title, description, features, install steps, usage and '
            'contributing sections.',
        recommendedWhen: [
          'pubspec.yaml',
          'package.json',
          'pyproject.toml',
          'go.mod',
          'Cargo.toml',
          '*.sln',
        ],
        content: r'''# {{project}}

A short description of what this project does and who it is for.

## Features

- ...

## Getting started

### Requirements

- ...

### Install

```bash
git clone <repository-url>
cd {{project}}
```

## Usage

```bash
...
```

## Contributing

Issues and pull requests are welcome. Please open an issue before starting a
larger change.

## License

MIT
''',
      ),
      FileTemplate(
        id: 'application',
        name: 'Desktop / mobile app',
        description: 'A screenshot, requirements, build and run steps for an '
            'application.',
        content: r'''# {{project}}

Short description of the application.

![{{project}} screenshot](docs/screenshot.png)

## Requirements

- ...

## Build

```bash
...
```

## Run

```bash
...
```

## License

MIT
''',
      ),
      FileTemplate(
        id: 'library',
        name: 'Library / package',
        description: 'Installation, a usage example and an API table for a reusable '
            'package.',
        content: r'''# {{project}}

One-line summary of the package.

## Installation

```bash
...
```

## Usage

```dart
import 'package:{{project}}/{{project}}.dart';

void main() {
  // ...
}
```

## API

| API | Description |
| --- | --- |
| `...` | ... |

## License

MIT
''',
      ),
    ],
  ),
  RepoFileSpec(
    path: '.editorconfig',
    summary: 'Indentation rules for every editor',
    templates: [
      FileTemplate(
        id: 'default',
        name: 'Common settings',
        description: 'UTF-8, LF and two spaces by default, four for Java, C# and '
            'Python, tabs for Makefiles.',
        content: r'''# https://editorconfig.org
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2
trim_trailing_whitespace = true

[*.md]
trim_trailing_whitespace = false

[*.{kt,kts,java,cs,csproj,sln,py,rs}]
indent_size = 4

[Makefile]
indent_style = tab
''',
      ),
    ],
  ),
];

/// [existing] with [template] added after it, separated by one blank line.
///
/// An empty (or blank) file simply becomes the template, so appending to a new
/// file and replacing it give the same result.
String appendTemplate(String existing, String template) {
  final head = existing.trimRight();
  if (head.isEmpty) return template;
  return '$head\n\n$template';
}

/// [input] as a repository-relative path, or null when it is not usable.
///
/// Backslashes become `/`; absolute paths, `..` and empty segments are refused.
String? normalizeRepoFilePath(String input) {
  final path = input.trim().replaceAll('\\', '/');
  if (path.isEmpty) return null;
  if (path.startsWith('/') || RegExp(r'^[a-zA-Z]:').hasMatch(path)) return null;
  final segments = path.split('/');
  if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
  return path;
}
