import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/core/models.dart';
import 'package:clean_forum/core/parser.dart';
import 'package:clean_forum/core/site.dart';

void main() {
  final parser = ForumParser();
  final base = ForumSite.base;
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
