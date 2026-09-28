import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/session.dart';
import 'package:clean_forum/core/site.dart';
import 'package:clean_forum/ui/glass_pager.dart';
import 'package:clean_forum/ui/reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pager buttons retain independent actions and disabled states', (
    tester,
  ) async {
    final actions = <String>[];
    Future<void> show({bool busy = false}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 290,
              child: GlassPager(
                pageNumber: 2,
                onPrevious: busy ? null : () => actions.add('previous'),
                onRefresh: busy ? null : () => actions.add('refresh'),
                onNext: busy ? null : () => actions.add('next'),
              ),
            ),
          ),
        ),
      ),
    );
    await show();
    for (final action in ['Previous page', 'Refresh page', 'Next page']) {
      await tester.tap(find.byTooltip(action));
    }
    expect(actions, ['previous', 'refresh', 'next']);
    await show(busy: true);
    for (final action in ['Previous page', 'Refresh page', 'Next page']) {
      await tester.tap(find.byTooltip(action));
    }
    expect(actions.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'floating pager leaves the last floor visible and permits scrolling',
    (tester) async {
      tester.view.physicalSize = const Size(320, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final page = ForumPage(
        url: ForumSite.base.resolve('/threads/sample.1/'),
        title: 'Scrolling sample',
        kind: PageKind.posts,
        posts: List.generate(
          20,
          (index) => ForumPost(
            id: 'floor-$index',
            author: 'Member $index',
            number: '#${index + 1}',
            blocks: [
              BodyBlock(BlockKind.paragraph, runs: [TextRun('Post $index')]),
            ],
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 34),
              textScaler: TextScaler.linear(2),
            ),
            child: ReaderPage(source: DemoSource(), initial: page, demo: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      final controller = list.controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      // Lazy children may refine the total extent after the first jump.
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final lastFloor = tester.getRect(find.byKey(const ValueKey('floor-19')));
      final pager = tester.getRect(find.byType(GlassPager));
      expect(lastFloor.bottom, lessThan(pager.top));
      expect(pager.bottom, lessThanOrEqualTo(750 - 34));
      expect(pager.height, greaterThanOrEqualTo(56));
      final before = controller.offset;
      await tester.dragFrom(const Offset(160, 300), const Offset(0, 240));
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(before));
      expect(tester.takeException(), isNull);
    },
  );
}
