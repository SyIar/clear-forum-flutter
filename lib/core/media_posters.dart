import 'dart:async';
import 'dart:collection';

import 'package:html/parser.dart' as html;

import 'models.dart';
import 'site.dart';

typedef PosterLoader = Future<Uri?> Function(BodyBlock block);

/// Page-scoped metadata cache. No player scripts or media bytes are requested.
class MediaPosters {
  MediaPosters(this.readHTML);
  final Future<String?> Function(Uri) readHTML;
  final _cache = <Uri, Future<Uri?>>{};
  final _waiting = Queue<Completer<void>>();
  var _active = 0;
  var _closed = false;
  void dispose() {
    _closed = true;
  }

  static bool supported(Uri url) {
    if (url.scheme != 'https' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      return false;
    }
    final path = switch (url.host) {
      'turbo.cr' ||
      'www.turbo.cr' => r'^/(?:embed|v|d)/[A-Za-z0-9_-]{1,128}/?$',
      'cyberdrop.cr' || 'www.cyberdrop.cr' => r'^/e/[A-Za-z0-9_-]{1,128}/?$',
      _ => null,
    };
    return path != null && RegExp(path).hasMatch(url.path);
  }

  Future<Uri?> resolve(BodyBlock block) {
    if (_closed) return Future.value();
    if (block.posterUrl != null) return Future.value(block.posterUrl);
    final url = block.url;
    if (block.directMedia || url == null || !supported(url)) {
      return Future.value();
    }
    // A forum page has bounded content; never let an unusually large page queue
    // unlimited work or repeatedly retry failures as a row re-enters the viewport.
    if (!_cache.containsKey(url) && _cache.length >= 128) return Future.value();
    return _cache.putIfAbsent(url, () => _load(url));
  }

  Future<Uri?> _load(Uri url) async {
    if (_active >= 2) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _active++;
    }
    try {
      if (_closed) return null;
      final source = await readHTML(url);
      return source == null ? null : parse(source, url);
    } catch (_) {
      return null;
    } finally {
      if (_waiting.isEmpty) {
        _active--;
      } else {
        _waiting.removeFirst().complete();
      }
    }
  }

  static Uri? parse(String source, Uri page) {
    final doc = html.parse(source);
    for (final ad in doc.querySelectorAll(
      '.advertisement,.ad-container,.adContainer,.adsbygoogle,[data-ad-slot]',
    )) {
      ad.remove();
    }
    final videos = doc.querySelectorAll('video');
    final primary = videos.where((v) => v.id == 'main-video').toList();
    final candidates = <String?>[
      for (final video in primary.isEmpty ? videos : primary) ...[
        video.attributes['poster'],
        video.attributes['data-poster'],
      ],
      doc.querySelector('meta[property="og:image"]')?.attributes['content'],
      doc.querySelector('meta[name="twitter:image"]')?.attributes['content'],
    ];
    for (final raw in candidates) {
      final poster = ForumSite.resolve(raw, page);
      if (poster != null &&
          poster.port == 443 &&
          poster.toString().length <= 8192) {
        return poster;
      }
    }
    return null;
  }
}
