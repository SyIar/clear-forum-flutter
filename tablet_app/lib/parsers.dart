import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'body_parser.dart';
import 'models.dart';
import 'site.dart';
import 'strings.dart';

String textOf(Element? e) =>
    e?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

extension Ancestors on Element {
  Iterable<Element> get parents sync* {
    var node = parent;
    while (node != null) {
      yield node;
      node = node.parent;
    }
  }
}

class PageParser {
  PageParser(this.site);
  final ForumSite site;
  ForumPage parse(String source, Uri url) {
    if (source.length > 8 * 1024 * 1024) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    if (site.module == Module.simp) return SimpParser(site).parse(source, url);
    if (site.module == Module.bookhouse && source.trimLeft().startsWith('[')) {
      return _bookRows(jsonDecode(source) as List, url);
    }
    final doc = html.parse(source);
    if (site.module == Module.bookhouse &&
        url.queryParameters['act'] == 'ajax') {
      return _bookRows(jsonDecode(doc.body?.text ?? source) as List, url);
    }
    if (site.module == Module.bookhouse) return _book(doc, source, url);
    return _south(doc, url);
  }

  ForumEntry bookEntry(
    String title,
    Uri url,
    String uploader, {
    String date = '',
    String authorID = '',
  }) {
    final author = AppStrings.pattern('bookAuthorPattern').firstMatch(title);
    final tags = AppStrings.pattern('bookTagPattern')
        .allMatches(title)
        .map((m) => m[1]!)
        .toList();
    final display = title
        .replaceAll(AppStrings.pattern('bookTagPattern'), '')
        .replaceAll(AppStrings.pattern('bookAuthorPattern'), '')
        .trim();
    return ForumEntry(
      title: display,
      url: url,
      subtitle: author?[1] ?? uploader,
      date: date,
      tags: tags,
      authorID: authorID,
    );
  }

  ForumPage _book(Document doc, String source, Uri url) {
    final body = doc.querySelector('#content-section,.content-section');
    if (body != null) {
      final meta = embeddedJson('threadInfo', source) as Map? ?? {};
      return ForumPage(
        url: url,
        title: textOf(doc.querySelector('h1.main-title')),
        kind: PageKind.posts,
        posts: [
          ForumPost(
            id: url.queryParameters['tid'] ?? '$url',
            author:
                '${meta['username'] ?? textOf(doc.querySelector('.sender a'))}',
            authorID: '${meta['uid'] ?? ''}',
            date: textOf(doc.querySelector('.subtitle-line')),
            blocks: _bookBody(body, url),
          ),
        ],
      );
    }
    final embedded = embeddedJson('_PageData', source);
    if (embedded is List) return _bookRows(embedded, url);
    final entries = <ForumEntry>[];
    final seen = <String>{};
    for (final row in doc.querySelectorAll(
      '.thread-list > li, .post-list .post-item',
    )) {
      final a = row
          .querySelectorAll('a[href]')
          .where((a) => a.attributes['href']!.contains('threadview'))
          .firstOrNull;
      final link = site.resolve(a?.attributes['href'], url, internal: true);
      if (link == null || !seen.add('$link')) continue;
      entries.add(
        bookEntry(
          textOf(a),
          link,
          textOf(row.querySelector('font')),
          date: textOf(row.querySelector('i,time')),
        ),
      );
    }
    if (entries.isEmpty && doc.querySelector('.thread-list,#d_list') == null) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final current = site.pageNumber(url);
    final pages = doc
        .querySelectorAll('.pagination-bar a[href]')
        .map((e) => site.resolve(e.attributes['href'], url, internal: true))
        .nonNulls
        .toList();
    return ForumPage(
      url: url,
      title: url.queryParameters['keywords'] ?? tr('Bookhouse'),
      kind: PageKind.threads,
      entries: entries,
      pageNumber: current,
      previous: current > 1 ? site.pageUrl(url, current - 1) : null,
      next: entries.isNotEmpty && pages.any((e) => site.pageNumber(e) > current)
          ? site.pageUrl(url, current + 1)
          : null,
    );
  }

  List<BodyBlock> _bookBody(Element body, Uri url) {
    final pre = body.querySelector('pre');
    if (pre == null) return SimpParser(site).parseBody(body, url);
    for (final br in pre.querySelectorAll('br')) {
      br.replaceWith(Text('\n'));
    }
    return [
      for (final line in pre.text.split(RegExp(r'\r?\n+')))
        if (line.trim().isNotEmpty)
          BodyBlock(BlockKind.paragraph, runs: [TextRun(line.trim())]),
    ];
  }

  ForumPage _bookRows(List rows, Uri url) {
    final entries = rows
        .whereType<Map>()
        .where((r) => '${r['uptid'] ?? r['rootid'] ?? 0}' == '0')
        .map(
          (r) => bookEntry(
            html.parseFragment('${r['subject'] ?? ''}').text ?? '',
            site.home.replace(
              queryParameters: {
                'app': 'forum',
                'act': 'threadview',
                'tid': '${r['tid']}',
              },
            ),
            '${r['username'] ?? ''}',
            date: '${r['dateline'] ?? ''}',
            authorID: '${r['uid'] ?? ''}',
          ),
        )
        .where((r) => r.title.isNotEmpty)
        .toList();
    final ids =
        entries
            .map((e) => int.tryParse(e.url.queryParameters['tid'] ?? ''))
            .nonNulls
            .toList()
          ..sort();
    final cursor = int.tryParse(url.queryParameters['mtid'] ?? '');
    return ForumPage(
      url: url,
      title: tr('Bookhouse'),
      kind: PageKind.threads,
      entries: entries,
      next: ids.isNotEmpty && (cursor == null || ids.first < cursor)
          ? site.home.replace(
              queryParameters: {
                'app': 'forum',
                'act': 'ajax',
                'mtid': '${ids.first}',
                'aifilter': '0',
              },
            )
          : null,
    );
  }

  ForumPage _south(Document doc, Uri url) {
    final parser = SimpParser(site);
    final posts = <ForumPost>[];
    final used = <Element>{};
    for (final body in doc.querySelectorAll('.tpc_content,[data-post-body]')) {
      Element container = body;
      for (final ancestor in body.parents) {
        if (ancestor.classes.contains('js-post') ||
            ancestor.localName == 'table' ||
            ancestor.id.startsWith('read_') && ancestor.localName == 'table') {
          container = ancestor;
          break;
        }
      }
      if (container == body) container = body.parent?.parent ?? body;
      if (!used.add(container)) continue;
      final names = container.querySelectorAll('a[href*="u.php"]');
      final name =
          names
              .where(
                (e) =>
                    textOf(e).isNotEmpty && e.querySelector('b,strong') != null,
              )
              .firstOrNull ??
          names.where((e) => textOf(e).isNotEmpty).firstOrNull;
      final floorNodes = container.querySelectorAll(
        '.tiptop a,.floor,.post-number',
      );
      final floor = floorNodes
          .map(textOf)
          .map((t) => RegExp(r'^(?:B|#)(\d+)(?:F)?$').firstMatch(t)?[1])
          .nonNulls
          .firstOrNull;
      final blocks = <BodyBlock>[];
      for (final content in container.querySelectorAll(
        '.tpc_content,[data-post-body]',
      )) {
        blocks.addAll(parser.parseBody(content, url));
      }
      posts.add(
        ForumPost(
          id: container.id.isNotEmpty ? container.id : 'post-${posts.length}',
          author: textOf(name),
          number: '#${floor ?? (body.id == 'read_tpc' ? 0 : posts.length)}',
          authorID:
              RegExp(r'uid[=-](\d+)')
                  .firstMatch(name?.attributes['href'] ?? '')?[1] ??
              '',
          avatar: site.resolve(
            names
                .map((e) => e.querySelector('img')?.attributes['src'])
                .nonNulls
                .firstOrNull,
            url,
          ),
          date:
              RegExp(r'\d{4}-\d{1,2}-\d{1,2}(?:[ T]\d{1,2}:\d{2}(?::\d{2})?)?')
                  .firstMatch(textOf(container.querySelector('.tiptop')))
                  ?.group(0) ??
              '',
          blocks: blocks.isEmpty ? parser.parseBody(body, url) : blocks,
        ),
      );
    }
    final entries = <ForumEntry>[];
    final seen = <String>{};
    final list =
        doc.querySelector('#ajaxtable,#threadlist,.thread-list') ?? doc.body!;
    for (final a in list.querySelectorAll(
      'h3 a[href],.subject a[href],a.subject[href],a[id^="a_ajax_"],.thread-title a[href],h2 a[href]',
    )) {
      final link = site.resolve(a.attributes['href'], url, internal: true);
      if (link == null ||
          !const ['/read.php', '/thread.php'].contains(link.path) ||
          !seen.add('$link') ||
          textOf(a).isEmpty) {
        continue;
      }
      final row =
          a.parents.where((e) => e.localName == 'tr').firstOrNull ?? a.parent!;
      final author = row.querySelector('a[href*="u.php"]');
      entries.add(
        ForumEntry(
          title: textOf(a),
          url: link,
          subtitle: textOf(author),
          date: textOf(row.querySelector('.f10,.gray,time')),
          authorID:
              RegExp(r'uid[=-](\d+)')
                  .firstMatch(author?.attributes['href'] ?? '')?[1] ??
              '',
        ),
      );
    }
    if (posts.isEmpty && entries.isEmpty) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final current = site.pageNumber(url);
    final paging = doc
        .querySelectorAll(
          '.pages a[href],.pagination a[href],.page-nav a[href]',
        )
        .map((a) => site.resolve(a.attributes['href'], url, internal: true))
        .nonNulls
        .where(
          (u) =>
              u.path == url.path &&
              site.pageUrl(u, 1).replace(fragment: '') ==
                  site.pageUrl(url, 1).replace(fragment: ''),
        )
        .toList();
    final next = paging
        .where((u) => site.pageNumber(u) == current + 1)
        .firstOrNull;
    return ForumPage(
      url: url,
      title:
          textOf(doc.querySelector('#subject_tpc,h1,.thread-title')).isNotEmpty
          ? textOf(doc.querySelector('#subject_tpc,h1,.thread-title'))
          : textOf(doc.querySelector('title')),
      kind: posts.isNotEmpty
          ? PageKind.posts
          : entries.every((e) => e.url.path == '/thread.php')
          ? PageKind.forums
          : PageKind.threads,
      entries: entries,
      posts: posts,
      pageNumber: current,
      previous: current > 1 ? site.pageUrl(url, current - 1) : null,
      next: next,
    );
  }
}

Object? embeddedJson(String name, String source) {
  final match = RegExp('(?:const|let|var)\\s+${RegExp.escape(name)}\\s*=\\s*')
      .firstMatch(source);
  if (match == null) return null;
  var depth = 0, quoted = false, escaped = false;
  for (var i = match.end; i < source.length; i++) {
    final c = source[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        quoted = false;
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == '[' || c == '{') {
      depth++;
    } else if (c == ']' || c == '}') {
      if (--depth == 0) {
        try {
          return jsonDecode(source.substring(match.end, i + 1));
        } on FormatException {
          return null;
        }
      }
    } else if (depth == 0 && c.trim().isNotEmpty) {
      return null;
    }
  }
  return null;
}
