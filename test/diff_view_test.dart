import 'package:easygit/git/models.dart';
import 'package:easygit/state/repo_controller.dart';
import 'package:easygit/theme/ide_theme.dart';
import 'package:easygit/ui/diff/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('side-by-side keeps both columns on screen with very long lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final tab = DiffTab(
      id: 'wt:a.txt',
      change: const FileChange(path: 'a.txt', kind: ChangeKind.modified),
      leftTitle: 'HEAD',
      rightTitle: 'Working tree',
      loader: () async => DiffContent('one\ntwo\n', 'one\n${'x' * 600}\n'),
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildIdeTheme(Brightness.dark),
      home: Scaffold(body: DiffView(tab: tab)),
    ));
    await tester.pumpAndSettle();

    final right = tester.getTopLeft(find.text('Working tree'));
    expect(right.dx, greaterThan(0));
    expect(right.dx, lessThan(1200));
    expect(find.text('1 difference'), findsOneWidget);
  });
}
