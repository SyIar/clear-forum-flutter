import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'models.dart';
import 'site.dart';

class ForumParser {
  static const _unwanted =
      'script,style,object,embed,input,textarea,select,svg,noscript,.adsbygoogle,.advertisement,.ad-container,.adContainer,.ad-block,.sponsor,[data-ad],[data-ad-slot],[hidden]';
  ForumPage parse(String source, Uri url, {int status = 200}) {
    final doc = html.parse(source);
    final title = _text(doc.querySelector('h1.p-title-value'));
    final template = doc.documentElement?.attributes['data-template'] ?? '';
    final pageTitle = _text(doc.querySelector('title')).toLowerCase();
    if (status == 429) throw const ReaderFailure(FailureKind.rateLimit, 429);
    if ((doc.querySelector(
                  '#challenge-running, #challenge-form, .cf-turnstile',
                ) !=
                null &&
            title.isEmpty) ||
        pageTitle.contains('just a moment') ||
        pageTitle.contains('attention required')) {
      throw ReaderFailure(FailureKind.verification, status);
    }
    if (status == 401 || template == 'login' || url.path.startsWith('/login')) {
      throw ReaderFailure(FailureKind.login, status);
    }
    if (status == 403) throw const ReaderFailure(FailureKind.forbidden, 403);
    if (status < 200 || status >= 300) {
      throw ReaderFailure(FailureKind.network, status);
    }
    if (template == 'error' ||
        doc.querySelector('.blockMessage--error') != null) {
      throw ReaderFailure(
        doc.querySelector('form[action*="login"]') != null
            ? FailureKind.login
            : FailureKind.forbidden,
        status,
      );
    }
    for (final element in doc.querySelectorAll(_unwanted)) {
      element.remove();
    }
    final posts = <ForumPost>[];
    for (final article in doc.querySelectorAll('article.message--post')) {
      final body = article.querySelector('.message-body .bbWrapper');
      if (body == null) continue;
      final attribution = article.querySelector(
        '.message-attribution-main time',
      );
      posts.add(
        ForumPost(
          id: article.id,
          author: _text(article.querySelector('.message-name .username')),
          date: attribution?.attributes['datetime'] ?? _text(attribution),
          number:
              article
                  .querySelectorAll('.message-attribution-opposite a')
                  .map((a) => a.text.trim())
                  .where((text) => RegExp(r'^#[0-9,]+$').hasMatch(text))
                  .firstOrNull ??
              '',
          blocks: parseBody(body, url),
        ),
      );
    }
    final threads = <ForumEntry>[];
    final seen = <String>{};
    final threadRows = doc.querySelectorAll('.structItem--thread');
    for (final item in threadRows) {
      final anchor = item
          .querySelectorAll('.structItem-title a')
          .where((a) => !a.classes.contains('labelLink'))
          .firstOrNull;
      final link = ForumSite.resolve(
        anchor?.attributes['href'],
        url,
        internal: true,
      );
      if (link == null || !seen.add(link.toString())) continue;
      threads.add(
        ForumEntry(
          title: _text(anchor),
          url: link,
          subtitle: _text(item.querySelector('.structItem-minor .username')),
          pinned: item.querySelector('.structItem-status--sticky') != null,
        ),
      );
    }
    final forums = <ForumEntry>[];
    for (final node in doc.querySelectorAll('.node')) {
      final anchor = node.querySelector('.node-title a');
      final link = ForumSite.resolve(
        anchor?.attributes['href'],
        url,
        internal: true,
      );
      if (link == null || !seen.add(link.toString())) continue;
      forums.add(
        ForumEntry(
          title: _text(anchor),
          url: link,
          subtitle: _text(node.querySelector('.node-description')),
        ),
      );
    }
    PageKind kind;
    if (posts.isNotEmpty || template == 'thread_view') {
      kind = PageKind.posts;
    } else if (threads.isNotEmpty ||
        template == 'forum_view' ||
        template == 'watched_threads_list' ||
        template == 'search_forum_view') {
      kind = PageKind.threads;
    } else if (forums.isNotEmpty || template == 'forum_list') {
      kind = PageKind.forums;
    } else {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    if (kind == PageKind.posts && posts.isEmpty) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    if (kind == PageKind.threads && threadRows.isNotEmpty && threads.isEmpty) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    return ForumPage(
      url: url,
      title: title.isEmpty ? 'Forums' : title,
      kind: kind,
      entries: [...forums, ...threads],
      posts: posts,
      previous: _paging(doc, url, 'prev'),
      next: _paging(doc, url, 'next'),
      pageNumber:
          int.tryParse(_text(doc.querySelector('.pageNav-page--current'))) ?? 1,
      loggedIn: doc.documentElement?.attributes['data-logged-in'] == 'true',
    );
  }

  Uri? _paging(Document doc, Uri url, String direction) {
    final link =
        doc.querySelector('.pageNav-jump--$direction') ??
        doc.querySelector('link[rel="$direction"]');
    return ForumSite.resolve(link?.attributes['href'], url, internal: true);
  }

  double? _aspectRatio(Element node) {
    final width = double.tryParse(node.attributes['width'] ?? '');
    final height = double.tryParse(node.attributes['height'] ?? '');
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return null;
    }
    final ratio = width / height;
    return ratio.isFinite && ratio > 0 ? ratio : null;
  }

  Uri? _poster(Element node, Uri page) {
    for (final name in ['poster', 'data-poster']) {
      final poster = ForumSite.resolve(node.attributes[name], page);
      if (poster != null) return poster;
    }
    return null;
  }

  List<BodyBlock> parseBody(Element root, Uri page) {
    final blocks = <BodyBlock>[];
    var runs = <TextRun>[];
    void flush() {
      if (runs.any((r) => r.text.trim().isNotEmpty)) {
        blocks.add(BodyBlock(BlockKind.paragraph, runs: List.of(runs)));
      }
      runs = [];
    }

    void walk(Node node, {bool bold = false, bool italic = false, Uri? href}) {
      if (node is Text) {
        runs.add(
          TextRun(
            node.text.replaceAll(RegExp(r'[\t\r\n ]+'), ' '),
            bold: bold,
            italic: italic,
            url: href,
          ),
        );
        return;
      }
      if (node is! Element) return;
      final tag = node.localName;
      if (const {
        'script',
        'style',
        'object',
        'embed',
        'form',
        'input',
        'textarea',
        'select',
        'svg',
        'noscript',
      }.contains(tag)) {
        return;
      }
      if (node.attributes.containsKey('hidden') ||
          node.classes.any(
            (c) => const {
              'advertisement',
              'ad-container',
              'adContainer',
              'ad-block',
              'adsbygoogle',
              'sponsor',
            }.contains(c),
          ) ||
          node.attributes.containsKey('data-ad') ||
          node.attributes.containsKey('data-ad-slot')) {
        return;
      }
      if (node.classes.contains('bbCodeBlock--unfurl')) {
        flush();
        final anchor = node.querySelector('.js-unfurl-title a');
        final url = ForumSite.resolve(anchor?.attributes['href'], page);
        if (url != null) {
          blocks.add(
            BodyBlock(
              BlockKind.link,
              url: url,
              label: _text(anchor).isEmpty ? url.host : _text(anchor),
            ),
          );
        }
        return;
      }
      if (tag == 'img') {
        final alt = node.attributes['alt'] ?? '';
        if (node.classes.contains('smilie')) {
          runs.add(TextRun(alt));
          return;
        }
        flush();
        final link = ForumSite.resolve(
          node.attributes['data-src']?.trim().isNotEmpty == true
              ? node.attributes['data-src']
              : node.attributes['src'],
          page,
        );
        if (link != null) {
          blocks.add(
            BodyBlock(
              BlockKind.image,
              url: link,
              label: alt.isEmpty ? 'Image' : alt,
              aspectRatio: _aspectRatio(node),
            ),
          );
        }
        return;
      }
      if (tag == 'iframe' || tag == 'video' || tag == 'audio') {
        flush();
        final candidates = [
          node.attributes['src'],
          node.attributes['data-src'],
          if (tag != 'iframe')
            node.querySelector('source[src]')?.attributes['src'],
        ];
        final source = ForumSite.resolve(
          candidates
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .firstOrNull,
          page,
        );
        blocks.add(
          BodyBlock(
            BlockKind.embeddedMedia,
            label: source?.host ?? 'Embedded media',
            url: source,
            posterUrl: _poster(node, page),
            aspectRatio: _aspectRatio(node),
            directMedia: tag != 'iframe',
          ),
        );
        return;
      }
      if (tag == 'blockquote' || node.classes.contains('bbCodeBlock--quote')) {
        flush();
        final content =
            node.querySelector(
              '.bbCodeBlock-expandContent, .bbCodeBlock-content',
            ) ??
            node;
        blocks.add(
          BodyBlock(
            BlockKind.quote,
            label: _text(node.querySelector('.bbCodeBlock-title')),
            children: parseBody(content, page),
          ),
        );
        return;
      }
      if (node.classes.contains('bbCodeSpoiler')) {
        flush();
        final content = node.querySelector('.bbCodeSpoiler-content');
        blocks.add(
          BodyBlock(
            BlockKind.spoiler,
            label: 'Spoiler',
            children: content == null ? [] : parseBody(content, page),
          ),
        );
        return;
      }
      if (node.classes.contains('bbCodeInlineSpoiler')) {
        flush();
        blocks.add(
          BodyBlock(
            BlockKind.spoiler,
            label: 'Spoiler',
            children: [
              BodyBlock(BlockKind.paragraph, runs: [TextRun(node.text)]),
            ],
          ),
        );
        return;
      }
      if (tag == 'pre') {
        flush();
        blocks.add(BodyBlock(BlockKind.code, label: node.text));
        return;
      }
      if (tag == 'br') {
        runs.add(const TextRun('\n'));
        return;
      }
      final boundary = const {
        'p',
        'div',
        'li',
        'ul',
        'ol',
        'h1',
        'h2',
        'h3',
        'h4',
        'table',
        'tr',
      }.contains(tag);
      if (boundary) flush();
      if (tag == 'li') runs.add(const TextRun('\u2022 '));
      final link = tag == 'a'
          ? ForumSite.resolve(node.attributes['href'], page)
          : href;
      for (final child in node.nodes) {
        walk(
          child,
          bold:
              bold ||
              const {'b', 'strong', 'h1', 'h2', 'h3', 'h4'}.contains(tag),
          italic: italic || const {'i', 'em'}.contains(tag),
          href: link,
        );
      }
      if (boundary) flush();
    }

    for (final child in root.nodes) {
      walk(child);
    }
    flush();
    return blocks;
  }

  String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
}
