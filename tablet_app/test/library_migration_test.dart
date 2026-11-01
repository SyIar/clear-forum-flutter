import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:forum_tablet/library.dart';
import 'package:forum_tablet/forum_identity.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/parsers.dart';
import 'package:forum_tablet/site.dart';

const simp = ForumSite(Module.simp), south = ForumSite(Module.south);
ForumPage thread(
  ForumSite site,
  int page,
  int total,
  int floor, {
  String slug = 'sample',
}) => ForumPage(
  url: site.module == Module.simp
      ? site.home.resolve('/threads/$slug.20/${page > 1 ? 'page-$page' : ''}')
      : site.home.resolve('/read.php?tid=20&page=$page'),
  title: 'A thread',
  kind: PageKind.posts,
  pageNumber: page,
  totalPages: total,
  next: page < total
      ? site.pageUrl(
          site.module == Module.simp
              ? site.home.resolve('/threads/$slug.20/')
              : site.home.resolve('/read.php?tid=20'),
          page + 1,
        )
      : null,
  lastPage: page < total
      ? site.pageUrl(
          site.module == Module.simp
              ? site.home.resolve('/threads/$slug.20/')
              : site.home.resolve('/read.php?tid=20'),
          total,
        )
      : null,
  posts: [
    ForumPost(
      id: 'post-$floor',
      author: 'Writer',
      authorID: '42',
      number: '#$floor',
      blocks: const [],
    ),
  ],
);
Future<LibraryStore> library(ForumSite site) async =>
    LibraryStore(await SharedPreferences.getInstance(), site: site);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Page metadata advances the bookmark destination without rewriting imported URL or marking floors read', () async {
    final store = await library(simp);
    final saved = ForumEntry(
      title: 'Custom label',
      url: simp.home.resolve('/threads/old-name.20/page-2#post-40'),
    );
    await store.toggle(saved);
    await store.observePage(thread(simp, 2, 8, 40, slug: 'new-name'));
    expect(store.bookmarks.single.url, saved.url);
    expect(store.destination(saved).path, '/threads/old-name.20/page-8');
    expect(store.destination(saved).fragment, isEmpty);
    expect(store.stateFor(saved.url)!.viewed, isNull);
    expect(store.stateFor(saved.url)!.checked, 0);
    await store.observePage(thread(simp, 1, 3, 20), live: false);
    expect(store.destination(saved).path, endsWith('page-8'));
    final restored = await library(simp);
    expect(
      restored.destination(restored.bookmarks.single),
      store.destination(saved),
    );
    await restored.toggle(saved.copyWith(url: restored.destination(saved)));
    expect(restored.bookmarks, isEmpty);
  });
  test(
    'Visible floor high-water mark persists when returning to an earlier page',
    () async {
      final store = await library(south),
          later = thread(south, 3, 3, 55),
          earlier = thread(south, 1, 3, 2);
      await store.visit(ForumEntry(title: 'Thread', url: later.url));
      await store.observePage(later);
      expect(store.stateFor(later.url)!.viewed, isNull);
      await store.recordVisible(later, later.posts.single);
      await store.recordVisible(earlier, earlier.posts.single);
      expect(store.stateFor(later.url)!.viewed, 55);
      expect(store.history.single.url.fragment, 'post-2');
      expect((await library(south)).stateFor(later.url)!.viewed, 55);
    },
  );
  test('Checks use real terminal-page floors and never overwrite the reading baseline', () async {
    final store = await library(simp),
        initial = thread(simp, 1, 3, 20),
        finalPage = thread(simp, 3, 3, 57);
    await store.toggle(ForumEntry(title: 'Thread', url: initial.url));
    await store.recordVisible(initial, initial.posts.single);
    final fetched = <Uri>[];
    await store.check((url) async {
      fetched.add(url);
      return simp.pageNumber(url) == 1 ? initial : finalPage;
    });
    expect(fetched.length, 2);
    expect(store.stateFor(initial.url)!.latest, 57);
    expect(store.stateFor(initial.url)!.viewed, 20);
    expect(store.stateFor(initial.url)!.updated, isTrue);
    await store.check(
      (_) async => throw StateError('Fresh rows must not fetch'),
      manual: true,
    );
    expect(store.updateStatus[simp.threadKey(initial.url)], 'Checked recently');
  });
  test('Automatic retries are throttled while manual failure retries remain eligible', () async {
    final store = await library(simp), initial = thread(simp, 1, 1, 4);
    await store.toggle(ForumEntry(title: 'Thread', url: initial.url));
    var requests = 0;
    Future<ForumPage> fail(Uri _) async {
      requests++;
      throw const ReaderFailure(FailureKind.network);
    }

    await store.check(fail);
    await store.check(fail);
    expect(requests, 1);
    await store.check(fail, manual: true);
    expect(requests, 2);
    expect(store.stateFor(initial.url)!.latest, isNull);
  });
  test('Author topics are validated and removing a follow during a request cannot resurrect it', () async {
    final store = await library(south),
        post = thread(south, 1, 1, 0).posts.single;
    await store.follow(post);
    final response = Completer<ForumPage>();
    final task = store.check((_) => response.future, manual: true);
    await Future<void>.delayed(Duration.zero);
    await store.block(post.authorID, post.author);
    response.complete(
      ForumPage(
        url: south.authorTopics('42')!,
        title: 'Writer',
        kind: PageKind.threads,
        entries: [
          ForumEntry(
            title: 'Topic',
            url: south.home.resolve('/read.php?tid=21'),
            authorID: '42',
          ),
        ],
      ),
    );
    await task;
    expect(store.authors, isEmpty);
    expect((await library(south)).blocked['42'], 'Writer');
  });
  test('Corrupt state is preserved instead of silently replaced', () async {
    SharedPreferences.setMockInitialValues({'forum.library.v2': '{broken'});
    final store = await library(south);
    expect(store.readOnly, isTrue);
    await store.toggle(
      ForumEntry(title: 'New', url: south.home.resolve('/read.php?tid=20')),
    );
    expect(store.preferences.getString('forum.library.v2'), '{broken');
  });
  test('South declared final page is required and quoted pagination cannot establish maximum floor', () {
    final url = south.home.resolve('/read.php?tid=20&page=2');
    const body =
        '<table class="js-post"><tr><td><a href="u.php?uid=42"><b>Writer</b></a><div class="tiptop"><a>#12</a></div><div class="tpc_content" id="read_987">Body</div></td></tr></table>';
    expect(PageParser(south).parse(body, url).maximumPostNumber, isNull);
    expect(
      PageParser(south)
          .parse(
            '$body<blockquote><div class="pagesone">Pages: 2/2</div></blockquote>',
            url,
          )
          .maximumPostNumber,
      isNull,
    );
    expect(
      PageParser(south)
          .parse('$body<div class="pagesone">Pages: 2/2</div>', url)
          .maximumPostNumber,
      12,
    );
  });
  test('South author topic routes and directory origin hints retain proper identity', () {
    final url = south.authorTopics('42')!;
    expect(south.readable(url), isTrue);
    expect(
      south.readable(south.home.resolve('/u.php?action-delete-uid-42.html')),
      isFalse,
    );
    final filtered = south.canonical(
      south.home.resolve('/read.php?tid-20-uid-42-fpage-2-page-3.html'),
    );
    expect(filtered.query, 'tid-20-uid-42-page-3.html');
    expect(south.threadRoot(filtered)!.query, 'tid=20');
    const source =
        '<div id="u-top"><h1 class="u-h1">Account ID</h1></div><div id="u-contentmain"><table class="u-table"><tr><td><a href="read.php?tid-21.html">Topic</a></td></tr></table></div>';
    final page = PageParser(south).parse(source, url);
    expect(page.kind, PageKind.threads);
    expect(page.entries.single.authorID, '42');
  });
}
