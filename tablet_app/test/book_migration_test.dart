import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum_tablet/books.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/session.dart';
import 'package:forum_tablet/site.dart';
import 'package:forum_tablet/strings.dart';

const site = ForumSite(Module.bookhouse);
Uri url(int id) => site.home.replace(
  queryParameters: {'app': 'forum', 'act': 'threadview', 'tid': '$id'},
);

class CacheSession extends ForumSession {
  CacheSession() : super(site);
  final Map<Uri, PageCapture> pages = {};
  int reads = 0;
  @override
  Future<PageCapture?> cached(Uri url) async => pages[url.removeFragment()];
  @override
  Future<PageCapture> fetch(Uri url, {bool offline = false}) async {
    reads++;
    throw const ReaderFailure(FailureKind.network);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> sample;
  setUpAll(() async {
    await AppStrings.load();
    sample = jsonDecode(
      File('test/fixtures/chapter_samples.md').readAsStringSync(),
    ) as Map<String, dynamic>;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  BookChapter chapter(String key, int id) =>
      BookChapter(ForumEntry(title: sample[key] as String, url: url(id)));
  List<BodyBlock> blocks(String key) => [
    for (final text in sample[key] as List) ...[
      BodyBlock(BlockKind.paragraph, runs: [TextRun(text as String)]),
      const BodyBlock(
        BlockKind.paragraph,
        runs: [TextRun('Body with a needle in this paragraph.')],
      ),
    ],
  ];
  test(
    'Chapter numerals, bundled ranges and split parts preserve identity',
    () {
      for (final e in (sample['numbers'] as Map).entries) {
        expect(chapterNumber(e.key as String), e.value);
      }
      expect(chapter('bundle', 1).first, 12);
      expect(chapter('bundle', 1).last, 14);
      expect(chapter('upper', 2).part, 1);
      expect(chapter('lower', 3).part, 3);
      expect(chapter('extra', 4).extra, isTrue);
      expect(chapterNumber('broken'), isNull);
    },
  );
  test('Overlaps trim at verified headings, preserve parts and refuse guessed boundaries', () {
    final boundary = BookSlice(chapter('bundle', 1), const []);
    final incoming = BookSlice(chapter('overlap', 2), blocks('headings'));
    expect(incoming.joined(boundary, before: false).start, 2);
    final previous = BookSlice(
      chapter('previous', 3),
      blocks('previousHeadings'),
    );
    expect(previous.joined(boundary, before: true).end, 4);
    expect(
      () => BookSlice(
        chapter('overlap', 2),
        const [],
      ).joined(boundary, before: false),
      throwsFormatException,
    );
    final lower = BookSlice(chapter('lower', 4), blocks('headings'));
    expect(
      lower
          .joined(BookSlice(chapter('upper', 5), const []), before: false)
          .start,
      0,
    );
    final anchors = ChapterAnchors(blocks('headings'), chapter('overlap', 2));
    expect(anchors.chapterAt(3, 14), 15);
  });
  test('Resume anchors survive restart and chapter slider targets bundled publications', () async {
    final preferences = await SharedPreferences.getInstance();
    final library = BookLibrary(preferences, CacheSession());
    final book = FollowedBook(
      title: 'Example',
      author: 'Writer',
      chapters: [
        chapter('bundle', 1),
        chapter('overlap', 2),
        chapter('upper', 3),
        chapter('lower', 4),
        chapter('extra', 5),
      ],
    );
    library.books.add(book);
    expect(library.jumpTo(book, 15), url(2).replace(fragment: 'chapter-15'));
    expect(
      library.jumpTo(book, 2, extra: true),
      url(5).replace(fragment: 'chapter-2'),
    );
    expect(library.jumpTo(book, 8), isNull);
    expect(library.adjacent(url(3), 1), url(4));
    await library.record(url(2).replace(fragment: 'novel-p-3'), chapter: 15);
    final restored = BookLibrary(preferences, CacheSession()).books.single;
    expect(restored.readChapter, 15);
    expect(restored.current?.entry.url, url(2));
    expect(restored.position?.fragment, 'novel-p-3');
  });
  test(
    'Cached search returns precise paragraph anchors without network requests',
    () async {
      final session = CacheSession();
      session.pages[url(1)] = PageCapture(
        url(1),
        '<h1 class="main-title">Example</h1><div id="content-section"><pre>Opening\nA needle in prose\nEnding needle</pre></div>',
        cached: true,
      );
      final library = BookLibrary(
        await SharedPreferences.getInstance(),
        session,
      );
      final book = FollowedBook(
        title: 'Example',
        author: 'Writer',
        chapters: [chapter('bundle', 1)],
      );
      final hits = await library.searchCache(book, 'needle');
      expect(hits.map((h) => h.$1.url.fragment), ['novel-p-1', 'novel-p-2']);
      expect(session.reads, 0);
    },
  );
  test('Successful checks are skipped for one hour while manual failed checks remain eligible', () async {
    final session = CacheSession();
    final library = BookLibrary(await SharedPreferences.getInstance(), session);
    final book = FollowedBook(
      title: 'Example',
      author: 'Writer',
      chapters: [chapter('bundle', 1)],
      checked: DateTime.now().millisecondsSinceEpoch,
    );
    library.books.add(book);
    await library.update(book, manual: true);
    expect(session.reads, 0);
    book.checked = 0;
    await library.update(book);
    await library.update(book);
    expect(session.reads, 1);
    await library.update(book, manual: true);
    expect(session.reads, 2);
  });
}
