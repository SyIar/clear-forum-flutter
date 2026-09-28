import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/main.dart';
import 'package:clean_forum/core/library.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/parser.dart';
import 'package:clean_forum/core/session.dart';
import 'package:clean_forum/core/site.dart';
import 'package:clean_forum/ui/reader.dart';

import 'library_test.dart' show MemoryLibraryStorage;
import 'sample_images.dart';

void main() {
  testWidgets('failed pagination retries the requested page', (tester) async {
    final source = _RetrySource();
    await tester.pumpWidget(
      MaterialApp(home: ReaderPage(source: source, demo: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(source.visited, [ForumSite.base, source.next, source.next]);
    expect(find.text('Page 2'), findsOneWidget);
  });
  testWidgets('sample mode has no empty account menu', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReaderPage(source: _LimitedSource(), demo: true)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });
  testWidgets('sample navigation shows native posts without ad content', (
    tester,
  ) async {
    await tester.pumpWidget(
      ClearForumApp(
        library: ReadingLibrary(sample: true, storage: MemoryLibraryStorage()),
      ),
    );
    await tester.tap(find.text('Explore sample reader'));
    await tester.pumpAndSettle();
    await preloadSampleImages(tester);
    expect(find.textContaining('SAMPLE CONTENT'), findsOneWidget);
    await tester.tap(find.text('Design & everyday things'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A calmer place to read'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.textContaining('DO NOT DISPLAY'), findsNothing);
    expect(find.textContaining('Hidden text stays hidden'), findsNothing);
    await tester.tap(find.text('Spoiler'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hidden text stays hidden'), findsOneWidget);
    expect(tester.takeException(), null);
  });
  testWidgets('rate limit is explicit and remains retryable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ReaderPage(source: _LimitedSource(), demo: true)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('limiting requests'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
  testWidgets('large text and a narrow dark screen do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = ForumParser().parse(
      File('assets/demo/thread.html').readAsStringSync(),
      ForumSite.base.resolve('/threads/quiet-reading.101/'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: ReaderPage(
            source: DemoSource(),
            initial: page,
            url: ForumSite.base.resolve('/threads/quiet-reading.101/'),
            demo: true,
          ),
        ),
      ),
    );
    await preloadSampleImages(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
  });
}

class _LimitedSource implements PageSource {
  @override
  Future<ForumPage> load(Uri url) async =>
      throw const ReaderFailure(FailureKind.rateLimit);
  @override
  Future<ForumPage?> openBrowser(Uri url) async => null;
  @override
  Future<void> clearSession() async {}
}

class _RetrySource implements PageSource {
  final next = ForumSite.base.resolve('/forums/sample.1/page-2');
  final visited = <Uri>[];
  @override
  Future<ForumPage> load(Uri url) async {
    visited.add(url);
    if (visited.length == 2) throw const ReaderFailure(FailureKind.network);
    return ForumPage(
      url: url,
      title: 'Sample',
      kind: PageKind.threads,
      next: url == next ? null : next,
      pageNumber: url == next ? 2 : 1,
    );
  }

  @override
  Future<ForumPage?> openBrowser(Uri url) async => null;
  @override
  Future<void> clearSession() async {}
}
