import 'package:flutter_test/flutter_test.dart';
import 'package:clean_forum/core/site.dart';

void main() {
  test('allows only HTTPS read routes on the exact origin', () {
    for (final value in [
      'https://simpcity.cr/',
      'https://simpcity.cr/forums/news.6/',
      'https://simpcity.cr/threads/topic.123/page-2',
      'https://simpcity.cr/threads/topic.123/?order=reaction_score',
    ]) {
      expect(ForumSite.readable(Uri.parse(value)), true, reason: value);
    }
    for (final value in [
      'http://simpcity.cr/',
      'https://simpcity.cr.example/',
      'https://simpcity.cr:8443/',
      'https://user:secret@simpcity.cr/',
      'https://simpcity.cr/logout/',
      'https://simpcity.cr/threads/topic.123/watch',
      'https://simpcity.cr/posts/123/react',
      'https://simpcity.cr/?_xfToken=secret',
      'https://simpcity.cr/?page=1&page=2',
      'https://simpcity.cr/?order=unknown',
    ]) {
      expect(ForumSite.readable(Uri.parse(value)), false, reason: value);
    }
  });
  test('Unicode thread slugs remain readable', () {
    expect(
      ForumSite.readable(
        Uri.parse('https://simpcity.cr/threads/%E6%B5%8B%E8%AF%95.123/'),
      ),
      true,
    );
  });
  test('links reject executable schemes and credential URLs', () {
    expect(ForumSite.resolve('javascript:alert(1)', ForumSite.base), null);
    expect(
      ForumSite.resolve('https://user:secret@example.com/', ForumSite.base),
      null,
    );
    expect(
      ForumSite.resolve('//example.com/image.png', ForumSite.base)?.host,
      'example.com',
    );
  });
  test('unread links resolve to canonical read routes', () {
    final page = ForumSite.base.resolve('/forums/sample.12/');
    for (final suffix in ['unread', 'unread/', 'unread?new=1']) {
      final link = ForumSite.resolve(
        '/threads/sample.42/$suffix',
        page,
        internal: true,
      );
      expect(link, ForumSite.base.resolve('/threads/sample.42/'));
      expect(ForumSite.readable(link!), true);
    }
    expect(
      ForumSite.resolve(
        '/threads/caf%C3%A9-%F0%9F%87%AC%F0%9F%87%A7.42/unread?new=1',
        page,
        internal: true,
      ),
      ForumSite.base.resolve('/threads/caf%C3%A9-%F0%9F%87%AC%F0%9F%87%A7.42/'),
    );
    expect(
      ForumSite.readable(page.resolve('/threads/sample.42/unread?new=1')),
      false,
    );
  });
  test('unread normalization does not broaden origin or action access', () {
    for (final path in [
      'https://outside.example/threads/sample.42/unread?new=1',
      'http://simpcity.cr/threads/sample.42/unread?new=1',
      'https://user:secret@simpcity.cr/threads/sample.42/unread?new=1',
      '/threads/sample.42/unread?new=1&new=1',
      '/threads/sample.42/unread?new=1&_xfToken=secret',
      '/threads/sample.42/unread?new=2',
      '/threads/sample.42/watch?new=1',
      '/threads/sample%252fwatch.42/unread?new=1',
    ]) {
      expect(
        ForumSite.resolve(path, ForumSite.base, internal: true),
        null,
        reason: path,
      );
    }
  });
}
