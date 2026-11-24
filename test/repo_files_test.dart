import 'dart:io';

import 'package:easygit/git/git_repository.dart';
import 'package:easygit/git/repo_file_entries.dart';
import 'package:easygit/git/repo_files.dart';
import 'package:easygit/state/accounts_store.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/theme/ide_theme.dart';
import 'package:easygit/ui/files/repo_files_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _git(String dir, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: dir);
  if (result.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${result.stderr}');
  }
}

/// Opens a repository with a Dart project file in [tmp].
Future<RepoController> _repository(Directory tmp) async {
  final dir = tmp.path.replaceAll('\\', '/');
  await _git(dir, ['init', '-b', 'main']);
  await _git(dir, ['config', 'user.email', 't@example.com']);
  await _git(dir, ['config', 'user.name', 'Tester']);
  await File('$dir/pubspec.yaml').writeAsString('name: demo\n');
  final ctrl = RepoController(await GitRepository.open(dir), AccountsStore());
  await ctrl.refreshAll();
  await ctrl.loadRepoFiles();
  return ctrl;
}

String _render(FileTemplate template) => template.render({
      'project': 'demo',
      'lfsUrl': 'https://lfs.example.com/team/demo',
    });

void main() {
  group('templates', () {
    test('specs are unique and their files end with a newline', () {
      final paths = [for (final spec in repoFileSpecs) spec.path];
      expect(paths.toSet().length, paths.length);
      expect(paths,
          containsAll(['.gitignore', '.gitattributes', '.lfsconfig', 'README.md']));
      for (final spec in repoFileSpecs) {
        expect(spec.templates, isNotEmpty, reason: spec.path);
        final ids = [for (final template in spec.templates) template.id];
        expect(ids.toSet().length, ids.length, reason: spec.path);
        for (final template in spec.templates) {
          expect(template.content.endsWith('\n'), isTrue,
              reason: '${spec.path}/${template.id}');
        }
      }
    });

    test('placeholders are replaced', () {
      final shared = RepoFileSpec.byPath('.lfsconfig')!
          .templates
          .firstWhere((t) => t.id == 'shared');
      final config = shared.render({'lfsUrl': 'https://lfs.example.com/team/app'});
      expect(config, contains('[lfs]'));
      expect(config, contains('url = https://lfs.example.com/team/app'));
      expect(config, isNot(contains('{{')));

      for (final template in RepoFileSpec.byPath('README.md')!.templates) {
        final readme = template.render({'project': 'EasyGit'});
        expect(readme, contains('EasyGit'), reason: template.id);
        expect(readme, isNot(contains('{{')), reason: template.id);
      }
    });

    test('the root of the repository suggests templates', () {
      final gitignore = RepoFileSpec.byPath('.gitignore')!;
      expect(gitignore.recommendedTemplate({'pubspec.yaml', 'lib'})!.id, 'dart');
      expect(gitignore.recommendedTemplate({'package.json'})!.id, 'node');
      expect(gitignore.recommendedTemplate({'demo.csproj'})!.id, 'dotnet');
      expect(gitignore.recommendedTemplate({'src', 'lib'}), isNull);
      expect(RepoFileSpec.byPath('README.md')!.recommendedTemplate({'go.mod'})!.id,
          'standard');
    });

    test('the LFS template writes real LFS attributes', () {
      final lfs = RepoFileSpec.byPath('.gitattributes')!
          .templates
          .firstWhere((t) => t.id == 'lfs');
      final psd = lfs.content.split('\n').firstWhere((l) => l.startsWith('*.psd'));
      expect(psd, contains('filter=lfs'));
      expect(psd, contains('diff=lfs'));
      expect(psd, contains('merge=lfs'));
      expect(psd, endsWith('-text'));
    });

    test('the shared LFS server template is valid git config', () async {
      final shared = RepoFileSpec.byPath('.lfsconfig')!
          .templates
          .firstWhere((t) => t.id == 'shared');
      final dir = Directory.systemTemp.createTempSync('easygit_lfsconfig');
      addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
      final file = File('${dir.path}/.lfsconfig');
      await file.writeAsString(
          shared.render({'lfsUrl': 'https://lfs.example.com/team/app'}));

      final result =
          await Process.run('git', ['config', '-f', file.path, '--get', 'lfs.url']);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect((result.stdout as String).trim(), 'https://lfs.example.com/team/app');
    });

    test('appending keeps the existing content', () {
      expect(appendTemplate('', '# A\n'), '# A\n');
      expect(appendTemplate('\n\n', '# A\n'), '# A\n');
      expect(appendTemplate('# A\n', '# B\n'), '# A\n\n# B\n');
      expect(appendTemplate('# A\n\n\n', '# B\n'), '# A\n\n# B\n');
    });
  });

  group('entries', () {
    test('every template is written back unchanged', () {
      for (final spec in repoFileSpecs) {
        if (repoFileFormat(spec.path) == RepoFileFormat.text) continue;
        for (final template in spec.templates) {
          final content = _render(template);
          final entries = parseFileEntries(spec.path, content);
          expect(entries, isNotNull, reason: spec.path);
          expect(entries!.toText(), content,
              reason: '${spec.path}/${template.id}');
        }
      }
    });

    test('files without a structure are plain text', () {
      expect(parseFileEntries('README.md', '# Hi\n'), isNull);
      expect(parseFileEntries('docs/NOTES.md', 'x'), isNull);
      expect(repoFileFormat('.gitignore'), RepoFileFormat.ignore);
      expect(repoFileFormat('sub/.gitattributes'), RepoFileFormat.attributes);
      expect(repoFileFormat('.lfsconfig'), RepoFileFormat.config);
      expect(repoFileFormat('.editorconfig'), RepoFileFormat.config);
      expect(repoFileFormat('README.md'), RepoFileFormat.text);
    });

    test('gitignore rules, comments and blanks', () {
      const source = '# build\nbuild/\n*.log\n!keep.log\n\n# ide\n.idea/\n';
      final entries = IgnoreEntries.parse(source);
      expect(entries.ruleCount, 4);
      expect(entries.rules.first.pattern, 'build/');
      expect(entries.rules.first.directory, isTrue);
      expect(entries.rules[1].directory, isFalse);
      expect(entries.rules[2].negated, isTrue);
      expect(entries.rules[2].path, 'keep.log');
      expect(entries.toText(), source);

      entries.addRule('  logs/  ');
      expect(entries.toText(), '${source}logs/\n');

      entries.updateRule(entries.rules[1], ' *.tmp ');
      expect(entries.toText(), contains('\n*.tmp\n'));

      entries.remove(entries.rules.last);
      expect(entries.toText(), isNot(contains('logs/')));
    });

    test('attribute rules keep their spacing until edited', () {
      const source = '*.psd    filter=lfs diff=lfs merge=lfs -text\n*.md text eol=lf\n';
      final entries = AttributeEntries.parse(source);
      expect(entries.ruleCount, 2);
      expect(entries.rules.first.pattern, '*.psd');
      expect(entries.rules.first.usesLfs, isTrue);
      expect(entries.rules.first.attributes,
          ['filter=lfs', 'diff=lfs', 'merge=lfs', '-text']);
      expect(entries.rules[1].usesLfs, isFalse);
      expect(entries.toText(), source);

      entries.updateRule(entries.rules.first, '*.psb', ['filter=lfs']);
      expect(entries.toText(), '*.psb filter=lfs\n*.md text eol=lf\n');

      entries.addRule('*.bin', ['binary']);
      expect(entries.toText(), endsWith('*.bin binary\n'));
    });

    test('config sections, entries and comments', () {
      const source = '# top\nroot = true\n\n[lfs]\n\turl = https://example.com/lfs\n';
      final entries = ConfigEntries.parse(source);
      expect(entries.sections.length, 2);
      expect(entries.sections.first.header, isNull);
      expect(entries.sections.first.pairs.single.key, 'root');
      expect(entries.sections.first.pairs.single.value, 'true');
      expect(entries.sections.last.name, 'lfs');
      expect(entries.pairCount, 2);
      expect(entries.toText(), source);

      final lfs = entries.sections.last;
      entries.updatePair(lfs, lfs.pairs.single, 'url', 'https://lfs.example.com/team/app');
      expect(entries.toText(),
          contains('[lfs]\n\turl = https://lfs.example.com/team/app\n'));

      entries.addPair(lfs, 'locksverify', 'true');
      expect(entries.toText(), endsWith('locksverify = true\n'));

      entries.addSection('*.md');
      expect(entries.toText(), endsWith('[*.md]\n'));
      expect(entries.sections.last.name, '*.md');

      entries.renameSection(entries.sections.last, '*.markdown');
      expect(entries.toText(), endsWith('[*.markdown]\n'));

      entries.removeLine(lfs, lfs.pairs.first);
      expect(entries.toText(), isNot(contains('https://lfs.example.com/team/app')));
    });

    test('line endings and the final newline survive', () {
      expect(IgnoreEntries.parse('a/\r\nb/\r\n').toText(), 'a/\r\nb/\r\n');
      expect(IgnoreEntries.parse('a/').toText(), 'a/');
      expect(IgnoreEntries.parse('').toText(), '');
      expect(ConfigEntries.parse('[lfs]\r\nurl = x\r\n').toText(),
          '[lfs]\r\nurl = x\r\n');
    });
  });

  group('file paths', () {
    test('accepts paths inside the repository', () {
      expect(normalizeRepoFilePath('.gitignore'), '.gitignore');
      expect(normalizeRepoFilePath('  docs/NOTES.md  '), 'docs/NOTES.md');
      expect(normalizeRepoFilePath(r'assets\notes.txt'), 'assets/notes.txt');
    });

    test('refuses absolute, empty and escaping paths', () {
      expect(normalizeRepoFilePath(''), isNull);
      expect(normalizeRepoFilePath('   '), isNull);
      expect(normalizeRepoFilePath('/etc/hosts'), isNull);
      expect(normalizeRepoFilePath(r'C:\Windows\win.ini'), isNull);
      expect(normalizeRepoFilePath('../secrets.txt'), isNull);
      expect(normalizeRepoFilePath('docs/../../x'), isNull);
      expect(normalizeRepoFilePath('docs//x'), isNull);
      expect(normalizeRepoFilePath('docs/'), isNull);
    });
  });

  testWidgets('a real repository creates and extends its files', (tester) async {
    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_repo_files');
      ctrl = await _repository(tmp);
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    final gitignore = RepoFileSpec.byPath('.gitignore')!;
    final dart = gitignore.recommendedTemplate(ctrl.repoRootEntries)!;
    expect(dart.id, 'dart');
    final secrets =
        gitignore.templates.firstWhere((template) => template.id == 'secrets');

    await tester.runAsync(() async {
      expect(ctrl.repoFileExists('.gitignore'), isFalse);
      await ctrl.openRepoFile('.gitignore');
      expect(ctrl.repoFile!.text, isEmpty);
      expect(ctrl.repoFile!.entries, isA<IgnoreEntries>());
      expect(ctrl.repoFileLoading, isFalse);

      // Create the file from the template the project suggests.
      expect(await ctrl.applyRepoFileTemplate(dart, append: false), isTrue);
      expect(File('${tmp.path}/.gitignore').readAsStringSync(), dart.content);
      expect(ctrl.repoFileExists('.gitignore'), isTrue);
      expect(ctrl.repoFile!.dirty, isFalse);
      expect(ctrl.status!.changes.any((c) => c.path == '.gitignore'), isTrue);
      expect(ctrl.changedRepoFileCount, 1);
      expect((ctrl.repoFile!.entries! as IgnoreEntries).ruleCount, greaterThan(5));

      // A new pattern marks the file dirty; saving writes it out.
      final entries = ctrl.repoFile!.entries! as IgnoreEntries;
      ctrl.updateRepoFile(() => entries.addRule('logs/'));
      expect(ctrl.repoFile!.dirty, isTrue);
      expect(await ctrl.saveRepoFile(), isTrue);
      expect(await File('${tmp.path}/.gitignore').readAsString(),
          '${dart.content}logs/\n');
      expect(ctrl.repoFile!.dirty, isFalse);

      // Appending a template keeps the patterns that are already there.
      expect(await ctrl.applyRepoFileTemplate(secrets, append: true), isTrue);
      final both = await File('${tmp.path}/.gitignore').readAsString();
      expect(both, contains('.dart_tool/'));
      expect(both, contains('logs/'));
      expect(both, contains('.env'));
      expect(both, appendTemplate('${dart.content}logs/\n', secrets.content));

      // Deleting puts the tab back to the template gallery.
      await ctrl.deleteRepoFile('.gitignore');
      expect(File('${tmp.path}/.gitignore').existsSync(), isFalse);
      expect(ctrl.repoFileExists('.gitignore'), isFalse);
      expect(ctrl.repoFile!.text, isEmpty);
      expect((ctrl.repoFile!.entries! as IgnoreEntries).ruleCount, 0);
    });

    await tester.runAsync(() async {
      // A README stays a plain-text file and gets the project name.
      final readme = RepoFileSpec.byPath('README.md')!.templates
          .firstWhere((template) => template.id == 'minimal');
      await ctrl.openRepoFile('README.md');
      expect(ctrl.repoFile!.entries, isNull);
      expect(await ctrl.applyRepoFileTemplate(readme, append: false), isTrue);
      final text = await File('${tmp.path}/README.md').readAsString();
      expect(text, startsWith('# ${ctrl.name}\n'));

      ctrl.repoFile!.controller.text = '# ${ctrl.name}\n\nEdited.\n';
      expect(ctrl.repoFile!.dirty, isTrue);
      expect(await ctrl.saveRepoFile(), isTrue);
      expect(await File('${tmp.path}/README.md').readAsString(),
          '# ${ctrl.name}\n\nEdited.\n');

      // Any other file can be added by hand and created empty.
      await ctrl.addRepoFile('docs/NOTES.md');
      expect(ctrl.repoFilePaths, contains('docs/NOTES.md'));
      expect(ctrl.repoFileExists('docs/NOTES.md'), isFalse);
      expect(await ctrl.saveRepoFile(), isTrue);
      expect(File('${tmp.path}/docs/NOTES.md').existsSync(), isTrue);
      expect(ctrl.repoFileExists('docs/NOTES.md'), isTrue);

      ctrl.forgetRepoFile('docs/NOTES.md');
      expect(ctrl.repoFilePaths, isNot(contains('docs/NOTES.md')));
      expect(ctrl.repoFile, isNull);
      expect(File('${tmp.path}/docs/NOTES.md').existsSync(), isTrue);
    });

    // Let the notification timers of the operations above run out.
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('the tab shows entries, the text editor and the gallery',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Directory tmp;
    late RepoController ctrl;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('easygit_repo_files_ui');
      ctrl = await _repository(tmp);
      await File('${tmp.path}/.gitignore')
          .writeAsString('# header\n.dart_tool/\nbuild/\n');
      await File('${tmp.path}/README.md').writeAsString('# Demo\n');
      await ctrl.loadRepoFiles();
      await ctrl.openRepoFile('.gitignore');
    });
    addTearDown(() async {
      ctrl.dispose();
      await tmp.delete(recursive: true).catchError((_) => tmp);
    });

    Future<void> showTab() async {
      await tester.pumpWidget(MaterialApp(
        theme: buildIdeTheme(Brightness.dark),
        home: Scaffold(body: RepoFilesView(ctrl: ctrl)),
      ));
      await tester.pump();
    }

    await showTab();
    expect(find.text('Repository Files'), findsOneWidget);
    // Listed on the left and open in the editor header on the right.
    expect(find.text('.gitignore'), findsNWidgets(2));
    expect(find.text('New File...'), findsOneWidget);
    // Patterns are rows, the comment is a note, and only the add field is a
    // text box.
    expect(find.text('.dart_tool/'), findsOneWidget);
    expect(find.text('build/'), findsOneWidget);
    expect(find.text('# header'), findsOneWidget);
    expect(find.text('Add Pattern'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // README is still edited as text.
    await tester.runAsync(() async => ctrl.openRepoFile('README.md'));
    await showTab();
    final editor = tester.widget<TextField>(find.byType(TextField));
    expect(editor.controller!.text, '# Demo\n');

    // A file that does not exist opens the template gallery instead.
    await tester.runAsync(() async => ctrl.openRepoFile('.editorconfig'));
    await showTab();
    expect(find.text('.editorconfig is not in the working tree yet'), findsOneWidget);
    expect(find.text('Common settings'), findsOneWidget);
    expect(find.text('Empty file'), findsOneWidget);
  });
}
