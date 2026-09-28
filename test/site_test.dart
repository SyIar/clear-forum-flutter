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
}
