import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/parser.dart';
import 'package:clean_forum/core/site.dart';

void main() {
  final parser = ForumParser();
  final base = ForumSite.base;
  test(
    'image metadata preserves lazy sources, dimensions and safe posters',
    () {
      final page = parser.parse(
        '''<html data-template="thread_view"><article class="message--post">
      <div class="message-body"><div class="bbWrapper">
        <img data-src="" src="/images/one.png" width="800" height="500">
        <img data-src="https://images.example/two.png" src="/placeholder.png" width="NaN" height="0">
        <video src="https://media.example/file.mp4" poster="/images/poster.png"></video>
        <iframe src="https://turbo.cr/embed/sample123"></iframe>
        <iframe src="https://turbo.cr.evil.example/embed/sample123"></iframe>
        <iframe src="https://turbo.cr:8443/embed/sample123"></iframe>
        <video src="https://media.example/file.mp4" poster="javascript:bad()"></video>
      </div></div></article></html>''',
        base,
      );
      final blocks = page.posts.single.blocks;
      expect(blocks[0].url, base.resolve('/images/one.png'));
      expect(blocks[0].aspectRatio, 1.6);
      expect(blocks[1].url?.host, 'images.example');
      expect(blocks[1].aspectRatio, null);
      expect(blocks[2].posterUrl, base.resolve('/images/poster.png'));
      expect(
        blocks[3].posterUrl,
        Uri.parse('https://cdn.turbo.cr/thumbs/sample123.jpg'),
      );
      expect(blocks[4].posterUrl, null);
      expect(blocks[5].posterUrl, null);
      expect(blocks[6].posterUrl, null);
    },
  );
  test('embed URLs are preserved without executing markup or keeping ads', () {
    final page = parser.parse('''<html data-template="thread_view"><article class="message--post" id="post-1">
      <div class="message-body"><div class="bbWrapper">
        <iframe src="https://player.example/embed/sample" onload="untrusted()"></iframe>
        <div class="advertisement"><iframe src="https://ads.example/"></iframe></div>
        <div class="bbCodeSpoiler"><div class="bbCodeSpoiler-content"><iframe src="https://player.example/embed/second"></iframe></div></div>
      </div></div></article></html>''', base);
    final body = page.posts.single.blocks;
    expect(body.length, 2);
    expect(body.first.kind, BlockKind.embeddedMedia);
    expect(body.first.label, 'player.example');
    expect(body.first.url, Uri.parse('https://player.example/embed/sample'));
    expect(body.first.directMedia, false);
    expect(body.last.children.single.kind, BlockKind.embeddedMedia);
  });
  test(
    'video source children resolve and remain distinct from iframe pages',
    () {
      final page = parser.parse(
        '''<html data-template="thread_view"><article class="message--post">
      <div class="message-body"><div class="bbWrapper"><video><source src="https://media.example/sample.m3u8"></video><iframe src="" data-src="https://player.example/embed/sample"></iframe><video src="javascript:bad()"></video></div></div>
      </article></html>''',
        base,
      );
      final blocks = page.posts.single.blocks;
      expect(blocks[0].directMedia, true);
      expect(blocks[0].url, Uri.parse('https://media.example/sample.m3u8'));
      expect(blocks[1].directMedia, false);
      expect(blocks[1].url?.host, 'player.example');
      expect(blocks[2].url, null);
    },
  );
  String fixture(String name) =>
      File('assets/demo/$name.html').readAsStringSync();
  Matcher failure(FailureKind kind) =>
      isA<ReaderFailure>().having((e) => e.kind, 'kind', kind);
  test('forum index extracts only forum nodes', () {
    final page = parser.parse(fixture('index'), base);
    expect(page.kind, PageKind.forums);
    expect(page.entries.length, 2);
    expect(page.entries.first.url.path, '/forums/design-notes.10/');
  });
  test('thread list keeps pinned state and skips prefix links', () {
    final page = parser.parse(
      fixture('forum'),
      base.resolve('/forums/design-notes.10/'),
    );
    expect(page.entries.length, 3);
    expect(page.entries.first.pinned, true);
    expect(page.entries[1].title, 'A calmer place to read');
  });
  test('inline moderation form does not erase the post list', () {
    final page = parser.parse(
      fixture('thread'),
      base.resolve('/threads/quiet-reading.101/'),
    );
    expect(page.posts.length, 2);
    expect(page.posts.first.author, 'Alex');
    expect(page.posts.first.number, '#1');
    final body = page.posts.first.blocks;
    expect(body.any((b) => b.kind == BlockKind.quote), true);
    expect(body.any((b) => b.kind == BlockKind.spoiler), true);
    expect(
      body.expand((b) => b.runs).any((r) => r.text.contains('DO NOT')),
      false,
    );
    expect(
      body
          .expand((b) => b.runs)
          .any((r) => r.bold && r.text.contains('less noise')),
      true,
    );
  });
  test('forum list keeps twenty unread threads alongside its pinned thread', () {
    final rows = List.generate(
      21,
      (i) =>
          '''
<div class="structItem structItem--thread ${i == 0 ? '' : 'is-unread'}">
  ${i == 0 ? '<i class="structItem-status--sticky"></i>' : ''}
  <div class="structItem-title">
    <a class="labelLink" href="/forums/sample.12/?prefix_id[0]=7">Category</a>
    <a data-tp-primary="on" href="/threads/sample.${100 + i}/${i == 0 ? '' : 'unread?new=1'}">Thread $i</a>
  </div>
</div>''',
    ).join();
    final page = parser.parse(
      '<html data-template="forum_view"><h1 class="p-title-value">Sample</h1>$rows<a class="pageNav-jump--next" href="page-2">Next</a></html>',
      base.resolve('/forums/sample.12/'),
    );
    expect(page.entries.length, 21);
    expect(page.entries.where((entry) => entry.pinned).length, 1);
    expect(page.entries[1].url, base.resolve('/threads/sample.101/'));
    expect(page.entries.last.url, base.resolve('/threads/sample.120/'));
    expect(page.next, base.resolve('/forums/sample.12/page-2'));
  });
  test(
    'unrecognized thread links fail instead of displaying an empty forum',
    () {
      expect(
        () => parser.parse(
          '<html data-template="forum_view"><div class="structItem--thread"><div class="structItem-title"><a href="/unrecognized/">A thread</a></div></div></html>',
          base.resolve('/forums/sample.12/'),
        ),
        throwsA(failure(FailureKind.unsupported)),
      );
    },
  );
  test('pagination resolves relative links without mixing origins', () {
    final source = fixture('thread').replaceFirst(
      '</body>',
      '<a class="pageNav-jump--next" href="page-2">Next</a><a class="pageNav-jump--prev" href="https://outside.example/threads/a.1/">Previous</a><li class="pageNav-page--current">1</li></body>',
    );
    final page = parser.parse(
      source,
      base.resolve('/threads/quiet-reading.101/'),
    );
    expect(
      page.next.toString(),
      'https://simpcity.cr/threads/quiet-reading.101/page-2',
    );
    expect(page.previous, null);
  });
  test('challenge is distinguished from a forbidden page', () {
    expect(
      () => parser.parse(
        '<title>Just a moment...</title><form id="challenge-form"></form>',
        base,
        status: 403,
      ),
      throwsA(failure(FailureKind.verification)),
    );
  });
  test('rate limit takes precedence over challenge markup', () {
    expect(
      () => parser.parse('<title>Just a moment...</title>', base, status: 429),
      throwsA(failure(FailureKind.rateLimit)),
    );
  });
  test('login template is not an empty forum', () {
    expect(
      () => parser.parse(
        '<html data-template="login"><h1>Login</h1></html>',
        base,
      ),
      throwsA(failure(FailureKind.login)),
    );
  });
  test('permission and server failures are explicit', () {
    expect(
      () => parser.parse('', base, status: 403),
      throwsA(failure(FailureKind.forbidden)),
    );
    expect(
      () => parser.parse('', base, status: 500),
      throwsA(failure(FailureKind.network)),
    );
  });
  test('unknown markup fails instead of claiming an empty result', () {
    expect(
      () => parser.parse('<html><body>Changed markup</body></html>', base),
      throwsA(failure(FailureKind.unsupported)),
    );
  });
  test('known empty forum remains a valid empty list', () {
    expect(
      parser
          .parse(
            '<html data-template="forum_view"><h1 class="p-title-value">Empty</h1></html>',
            base,
          )
          .entries,
      isEmpty,
    );
  });
  test('body discards active content and unsafe URLs', () {
    final source = fixture('thread').replaceFirst(
      'Good reading begins with',
      '<iframe src="https://ad.example/"></iframe><a href="javascript:alert(1)">Unsafe action</a><img src="data:image/png;base64,AAAA"><div data-ad-slot="slot">Hidden promotion</div>Good reading begins with',
    );
    final page = parser.parse(source, base);
    final runs = page.posts.first.blocks.expand((b) => b.runs).toList();
    expect(
      runs.where((r) => r.text.contains('Unsafe action')).single.url,
      null,
    );
    expect(runs.any((r) => r.text.contains('Hidden promotion')), false);
    expect(
      page.posts.first.blocks.where((b) => b.kind == BlockKind.image),
      isEmpty,
    );
  });
  test('expired login error is distinguished from permission denial', () {
    expect(
      () => parser.parse(
        '<html data-template="error"><form action="/login/"></form></html>',
        base,
      ),
      throwsA(failure(FailureKind.login)),
    );
  });
}
