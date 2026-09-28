import 'package:clean_forum/core/library.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/session.dart';
import 'package:clean_forum/core/site.dart';
import 'package:clean_forum/main.dart';
import 'package:clean_forum/ui/reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_test.dart' show MemoryLibraryStorage;
import 'sample_images.dart';

void main() {
  testWidgets('reader bookmark appears at home and reopens its URL', (
    tester,
  ) async {
    final library = ReadingLibrary(
      sample: true,
      storage: MemoryLibraryStorage(),
    );
    await tester.pumpWidget(ClearForumApp(library: library));
    await tester.pumpAndSettle();
    await preloadSampleImages(tester);
    await tester.tap(find.text('Explore sample reader'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Design & everyday things'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A calmer place to read'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bookmark page'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    expect(library.bookmarks.length, 1);
    expect(library.recent.first.url, library.bookmarks.single.url);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Bookmarks'), findsOneWidget);
    final saved = find.text(library.bookmarks.single.title).first;
    await tester.ensureVisible(saved);
    await tester.tap(saved);
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(tester.takeException(), null);
  });
  testWidgets('home accepts a local bookmark and rejects another site', (
    tester,
  ) async {
    final library = ReadingLibrary(
      sample: true,
      storage: MemoryLibraryStorage(),
    );
    await tester.pumpWidget(ClearForumApp(library: library));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add bookmark'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://outside.example/',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(library.bookmarks, isEmpty);
    expect(find.textContaining('Use an HTTPS'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'https://simpcity.cr/threads/sample.12/page-5#post-3',
    );
    await tester.enterText(find.byType(TextField).last, 'Saved location');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(library.bookmarks.single.url.fragment, 'post-3');
    expect(find.text('Saved location'), findsOneWidget);
  });
  testWidgets('iOS sample pages never pollute the live library', (
    tester,
  ) async {
    final library = ReadingLibrary(
      sample: false,
      storage: MemoryLibraryStorage(),
    );
    await library.load();
    await tester.pumpWidget(
      LibraryScope(
        library: library,
        child: MaterialApp(
          home: ReaderPage(
            source: DemoSource(),
            demo: true,
            initial: ForumPage(
              url: ForumSite.base,
              title: 'Sample',
              kind: PageKind.forums,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(library.recent, isEmpty);
    expect(find.byTooltip('Bookmark page'), findsNothing);
  });
  testWidgets('home supports narrow layout, dark appearance and larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      ClearForumApp(
        library: ReadingLibrary(sample: true, storage: MemoryLibraryStorage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
}
