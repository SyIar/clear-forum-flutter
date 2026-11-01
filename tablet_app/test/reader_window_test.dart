import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum_tablet/library.dart';
import 'package:forum_tablet/reader.dart';
import 'package:forum_tablet/session.dart';
import 'package:forum_tablet/site.dart';
import 'package:forum_tablet/strings.dart';

class WindowSession extends ForumSession {
  WindowSession() : super(const ForumSite(Module.south));
  final List<int> fetched = [];
  @override
  Future<PageCapture> fetch(Uri url, {bool offline = false}) async {
    final page = site.pageNumber(url);
    fetched.add(page);
    return PageCapture(
      url,
      '<h1 id="subject_tpc">Window</h1><div class="pagesone">Pages: $page/12 Go</div><table class="js-post" id="read_$page"><tr><td><a href="u.php?uid=9"><strong>Author $page</strong></a><div class="tiptop"><a>#$page</a></div><div class="tpc_content">${List.generate(16, (i) => '<p>Page $page paragraph $i with enough prose to scroll through the publication.</p>').join()}</div></td></tr></table>',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppStrings.load);
  testWidgets(
    'Prefetch does not mark unseen posts as read and the reader trims offscreen pages',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = WindowSession();
      final library = LibraryStore(
        await SharedPreferences.getInstance(),
        site: session.site,
      );
      final url = session.site.home.resolve('/read.php?tid=1');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThreadReader(
              url: url,
              session: session,
              library: library,
              onLink: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .controller!;
      for (var page = 1; page <= 7; page++) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        expect(session.fetched.contains(page + 1), isTrue);
        expect(library.stateFor(url)!.viewed, lessThanOrEqualTo(page));
      }
      expect(find.text('Author 1'), findsNothing);
      expect(find.text('Author 8'), findsOneWidget);
      expect(
        (tester.state(find.byType(ThreadReader)) as dynamic).retainedPageCount,
        lessThanOrEqualTo(5),
      );
      expect(tester.takeException(), isNull);
      final readBefore = library.stateFor(url)!.viewed;
      scroll.jumpTo(80);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, 250),
      );
      await tester.pumpAndSettle();
      expect(
        session.fetched.where((p) => p == 3).length,
        2,
        reason: 'requests=${session.fetched}, offset=${scroll.offset}',
      );
      expect(library.stateFor(url)!.viewed, readBefore);
      expect(
        (tester.state(find.byType(ThreadReader)) as dynamic).retainedPageCount,
        lessThanOrEqualTo(5),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    },
  );
}
