import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/main.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/parser.dart';
import 'package:clean_forum/core/session.dart';
import 'package:clean_forum/core/site.dart';
import 'package:clean_forum/ui/reader.dart';

void main() {
  testWidgets('sample navigation shows native posts without ad content', (
    tester,
  ) async {
    await tester.pumpWidget(const ClearForumApp());
    await tester.tap(find.text('Explore sample reader'));
    await tester.pumpAndSettle();
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
