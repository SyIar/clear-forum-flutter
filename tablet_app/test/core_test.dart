import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/books.dart';
import 'package:forum_tablet/body_parser.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/parsers.dart';
import 'package:forum_tablet/site.dart';
import 'package:forum_tablet/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(AppStrings.load);
  const south = ForumSite(Module.south),
      book = ForumSite(Module.bookhouse),
      simp = ForumSite(Module.simp);
  test('South normalization keeps author filtering and rejects actions', () {
    expect(
      south
          .canonical(south.home.resolve('read.php?tid-2973920-page-2.html'))
          .queryParameters,
      {'tid': '2973920', 'page': '2'},
    );
    final filter = south.home.resolve('read.php?tid-2973760-uid-1191634.html');
    expect(south.canonical(filter), filter);
    expect(
      south.pageUrl(filter, 2).query,
      'tid-2973760-uid-1191634-page-2.html',
    );
    for (final value in [
      'read.php?tid=1&action=delete',
      'read.php?tid=1&tid=2',
      'read.php?tid-1-action-delete.html',
      'https://south-plus.net.evil.invalid/read.php?tid=1',
      'https://user@south-plus.net/read.php?tid=1',
    ]) {
      expect(
        south.readable(south.canonical(south.home.resolve(value))),
        isFalse,
        reason: value,
      );
    }
  });
  test('South page 2 directory links resolve into readable routes', () {
    final page = PageParser(south).parse(
      '<title>Board</title><div id="ajaxtable"><h3><a href="read.php?tid-10.html">A post</a></h3></div><div class="pages"><a href="thread.php?fid-9-page-2.html">2</a></div>',
      south.home.resolve('thread.php?fid=9'),
    );
    expect(page.entries.single.title, 'A post');
    expect(page.next?.queryParameters, {'fid': '9', 'page': '2'});
  });
  test('South includes attachment-only sibling body and lazy image', () {
    final page = PageParser(south).parse(
      '''<h1 id="subject_tpc">Thread</h1><table class="js-post" id="post_10"><tr><td><a href="u.php?uid=5"><strong>Writer</strong></a><div class="tiptop"><a>#4</a></div><div class="tpc_content">Prose<img src="//south-plus.net/a.jpeg" loading="lazy"></div><div class="tpc_content"><a href="job.php?action-download-pid-10-tid-20-aid-30.html">archive.zip</a></div></td></tr></table>''',
      south.home.resolve('read.php?tid=20'),
    );
    expect(page.posts.length, 1);
    expect(page.posts.single.author, 'Writer');
    expect(page.posts.single.number, '#4');
    expect(
      page.posts.single.blocks.any(
        (b) => b.kind == BlockKind.image && b.url?.scheme == 'https',
      ),
      isTrue,
    );
    expect(
      page.posts.single.blocks
          .expand((b) => b.runs)
          .any((r) => r.url?.path == '/job.php'),
      isTrue,
    );
  });
  test(
    'Simp verification response is not an empty page and valid body wins',
    () {
      expect(
        () => SimpParser(simp).parse(
          '<title>DDoS-Guard</title><h1>Checking your browser</h1>',
          simp.home,
        ),
        throwsA(
          isA<ReaderFailure>().having(
            (e) => e.kind,
            'kind',
            FailureKind.verification,
          ),
        ),
      );
      final page = SimpParser(simp).parse(
        '<title>Forum</title><article class="message--post" id="post-1"><div class="message-body"><div class="bbWrapper">DDoS-Guard discussion</div></div></article>',
        simp.home.resolve('threads/example.1/'),
      );
      expect(page.posts.length, 1);
    },
  );
  test('Book title extracts literary author and tags while body stays unchanged', () {
    final fixture =
        jsonDecode(File('test/fixtures/books.json').readAsStringSync()) as Map;
    final parser = PageParser(book);
    final url = book.home.resolve('?app=forum&act=threadview&tid=20');
    final entry = parser.bookEntry(fixture['title'] as String, url, 'Uploader');
    expect(entry.title, fixture['display']);
    expect(entry.subtitle, fixture['author']);
    expect(entry.tags, [fixture['tag']]);
    final chapter = BookChapter(entry);
    expect(chapter.extra, isTrue);
    expect(chapter.first, 7);
    expect(chapter.last, 8);
    final page = parser.parse(
      '<h1 class="main-title">${fixture['title']}</h1><div id="content-section"><pre>${fixture['body']}</pre></div>',
      url,
    );
    expect(page.title, fixture['title']);
    expect(page.posts.single.blocks.length, 2);
    expect(page.posts.single.blocks.first.kind, BlockKind.paragraph);
  });
  test(
    'Book cursor response supports browser JSON document and skips replies',
    () {
      final url = book.home.replace(
        queryParameters: {
          'app': 'forum',
          'act': 'ajax',
          'mtid': '40',
          'aifilter': '0',
        },
      );
      final page = PageParser(book).parse(
        '<html><body><pre>[{"tid":"30","uptid":"0","subject":"Book","username":"Writer"},{"tid":"31","uptid":"30","subject":"Reply"}]</pre></body></html>',
        url,
      );
      expect(page.entries.length, 1);
      expect(page.next?.queryParameters['mtid'], '30');
    },
  );
  test('Embedded data extraction never evaluates scripts', () {
    expect(
      embeddedJson(
        '_PageData',
        'const _PageData = [{"subject":"a } b"}]; alert(1);',
      ),
      [
        {'subject': 'a } b'},
      ],
    );
    expect(
      embeddedJson('_PageData', 'const _PageData = loadSomething();'),
      isNull,
    );
  });
}
