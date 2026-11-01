import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'forum_identity.dart';
import 'forum_search.dart';

enum Module { tieba, simp, south, bookhouse }

class ForumSite {
  const ForumSite(this.module);
  final Module module;
  bool get supportsLogin => module == Module.simp || module == Module.south;
  Uri get login =>
      home.resolve(module == Module.simp ? '/login/' : '/login.php');
  bool isLogin(Uri url) =>
      supportsLogin &&
      sameOrigin(url) &&
      (module == Module.simp
          ? url.path.startsWith('/login')
          : url.path == '/login.php');
  static ForumSite get current => ForumSite(
    Module.values.byName(
      appFlavor ?? const String.fromEnvironment('FORUM', defaultValue: 'south'),
    ),
  );
  String get name => switch (module) {
    Module.tieba => 'Tieba',
    Module.simp => 'Simp',
    Module.south => 'South',
    Module.bookhouse => 'Bookhouse',
  };
  Color get color => switch (module) {
    Module.tieba => const Color(0xFF2467C9),
    Module.simp => const Color(0xFF006A70),
    Module.south => const Color(0xFF6A528E),
    Module.bookhouse => const Color(0xFF426749),
  };
  IconData get icon => switch (module) {
    Module.tieba => Icons.forum_outlined,
    Module.simp => Icons.apartment_rounded,
    Module.south => Icons.explore_outlined,
    Module.bookhouse => Icons.auto_stories_outlined,
  };
  Uri get home => Uri.parse(switch (module) {
    Module.tieba => 'https://tieba.baidu.com/',
    Module.simp => 'https://simpcity.cr/',
    Module.south => 'https://south-plus.net/index.php',
    Module.bookhouse => 'https://www.cool18.com/bbs4/index.php',
  });
  bool sameOrigin(Uri url) =>
      url.host == home.host &&
      url.scheme == 'https' &&
      url.port == 443 &&
      url.userInfo.isEmpty;
  bool readable(Uri url) {
    if (!sameOrigin(url) ||
        url.queryParametersAll.values.any((v) => v.length != 1)) {
      return false;
    }
    final q = url.queryParameters;
    if (module == Module.simp) {
      if (!q.keys.every(
        (key) => const [
          'page',
          'order',
          'direction',
          'q',
          'keywords',
          't',
          'c[users]',
          'c[thread]',
          'c[title_only]',
          'o',
        ].contains(key),
      )) {
        return false;
      }
      return url.path == '/' ||
          RegExp(
            r'^/(?:forums|threads)/[^/]+\.\d+(?:/page-\d+)?/?$|^/posts/\d+/?$|^/watched/threads/?$|^/members/[^/]+\.\d+/(?:recent-content|latest-activity)?/?$|^/search/(?:\d+/)?$',
          ).hasMatch(url.path);
    }
    if (module == Module.south) {
      if (url.path == '/search.php') {
        return ForumSearch.southParameters(url) != null;
      }
      if (url.path == '/index.php') return q.isEmpty;
      if (url.path == '/u.php') {
        if (!url.query.contains('=') &&
            !RegExp(
              r'^(?:action-topic-)?uid-[1-9]\d*(?:-page-[1-9]\d*)?\.html$',
            ).hasMatch(url.query)) {
          return false;
        }
        final fields = parameters(url);
        return fields.keys.every(
              (k) => ['uid', 'action', 'page'].contains(k),
            ) &&
            validAuthor(fields['uid'] ?? '') &&
            (fields['action'] == null || fields['action'] == 'topic');
      }
      if (!['/read.php', '/thread.php'].contains(url.path)) return false;
      if (!url.query.contains('=')) {
        return RegExp(
          r'^(?:tid|fid)-[1-9]\d*(?:-(?:page|uid|type)-[1-9]\d*)*\.html$',
        ).hasMatch(url.query);
      }
      if (!q.keys.every(
        (k) => ['tid', 'fid', 'uid', 'page', 'type', 'order'].contains(k),
      )) {
        return false;
      }
      return q.containsKey(url.path == '/read.php' ? 'tid' : 'fid') &&
          q.entries.every(
            (e) => e.key == 'order'
                ? ['postdate', 'lastpost'].contains(e.value)
                : RegExp(r'^[1-9]\d{0,10}$').hasMatch(e.value),
          );
    }
    if (module == Module.bookhouse) {
      if (url.path != '/bbs4/index.php') return false;
      if (q.isEmpty) return true;
      if (!q.keys.every(
        (k) => [
          'app',
          'act',
          'action',
          'tid',
          'mtid',
          'aifilter',
          'keywords',
          'type',
          'uid',
          'p',
          'bbsdr',
          'submit',
          'first',
        ].contains(k),
      )) {
        return false;
      }
      if (q['app'] != null && q['app'] != 'forum' ||
          q['bbsdr'] != null && q['bbsdr'] != 'bbs4') {
        return false;
      }
      if (q['action'] != null && q['action'] != 'search') return false;
      if (![
        'threadview',
        'threadsearch',
        'ajax',
        'achildlist',
      ].contains(q['act'])) {
        return false;
      }
      if (q['aifilter'] != null && q['aifilter'] != '0') return false;
      for (final key in ['tid', 'mtid', 'p']) {
        if (q[key] != null && !RegExp(r'^[1-9]\d{0,10}$').hasMatch(q[key]!)) {
          return false;
        }
      }
      return true;
    }
    return url.path.startsWith('/p/') || url.path == '/f';
  }

  Uri canonical(Uri url) {
    if (url.host != home.host &&
        !(module == Module.bookhouse && url.host == 'cool18.com')) {
      return url;
    }
    url = url.replace(scheme: 'https', host: home.host);
    if (module == Module.south && url.path == '/read.php') {
      if (url.query.contains('=')) {
        final hint = url.queryParameters['fpage'];
        if (hint != null && RegExp(r'^(?:0|[1-9]\d{0,4})$').hasMatch(hint)) {
          final fields = Map<String, String>.from(url.queryParameters)
            ..remove('fpage');
          url = url.replace(queryParameters: fields);
        }
      } else {
        url = url.replace(
          query: url.query.replaceFirst(
            RegExp(r'-fpage-(?:0|[1-9]\d{0,4})(?=-|\.html$)'),
            '',
          ),
        );
      }
    }
    if (module == Module.south &&
        (url.path == '/read.php' || url.path == '/thread.php') &&
        !url.query.contains('=')) {
      if (url.query.contains('-uid-') || !readable(url)) return url;
      final pairs = RegExp(r'(tid|fid|page|type|order)-([A-Za-z0-9_]+)')
          .allMatches(url.query.replaceFirst(RegExp(r'\.html$'), ''));
      if (pairs.isNotEmpty) {
        return url.replace(
          queryParameters: {for (final p in pairs) p[1]!: p[2]!},
        );
      }
    }
    if (module == Module.simp && url.path.endsWith('/unread')) {
      return url.replace(
        path: url.path.replaceFirst(RegExp(r'unread$'), ''),
        query: '',
      );
    }
    return url;
  }

  Uri? resolve(String? value, Uri page, {bool internal = false}) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final candidate = canonical(page.resolve(value.trim()));
      if (!const ['https', 'http'].contains(candidate.scheme) ||
          candidate.host.isEmpty ||
          candidate.userInfo.isNotEmpty) {
        return null;
      }
      if (internal && !readable(candidate)) return null;
      return candidate;
    } on FormatException {
      return null;
    }
  }

  int pageNumber(Uri url) =>
      int.tryParse(
        (module == Module.south && url.path == '/search.php'
                ? (ForumSearch.southParameters(url)?['page'])
                : null) ??
            url.queryParameters['page'] ??
            url.queryParameters['p'] ??
            RegExp(r'(?:page-|/page-)(\d+)').firstMatch(url.toString())?[1] ??
            '',
      ) ??
      1;
  Uri pageUrl(Uri url, int page) {
    if (module == Module.south && url.path == '/search.php') {
      final fields = ForumSearch.southParameters(url);
      if (fields != null) {
        return url.replace(
          queryParameters: {...fields, 'page': '$page'},
          fragment: '',
        );
      }
    }
    if (module == Module.simp) {
      if (url.path.startsWith('/search/') ||
          url.queryParameters.containsKey('page')) {
        return url.replace(
          queryParameters: {...url.queryParameters, 'page': '$page'},
          fragment: '',
        );
      }
      return url.replace(
        path:
            '${url.path.replaceFirst(RegExp(r'/page-\d+/?$'), '').replaceFirst(RegExp(r'/$'), '')}/${page == 1 ? '' : 'page-$page'}',
      );
    }
    if (module == Module.south &&
        !url.query.contains('=') &&
        url.query.endsWith('.html')) {
      final query = url.query
          .replaceFirst(RegExp(r'-page-\d+'), '')
          .replaceFirst('.html', '');
      return url.replace(query: '$query-page-$page.html');
    }
    return url.replace(
      queryParameters: {
        ...url.queryParameters,
        module == Module.bookhouse ? 'p' : 'page': '$page',
      },
    );
  }

  Uri search(String query) => switch (module) {
    Module.bookhouse => home.replace(
      queryParameters: {
        'action': 'search',
        'bbsdr': 'bbs4',
        'act': 'threadsearch',
        'app': 'forum',
        'keywords': query,
      },
    ),
    Module.south =>
      home.resolve('search.php').replace(queryParameters: {'keyword': query}),
    Module.simp =>
      home.resolve('search/').replace(queryParameters: {'keywords': query}),
    Module.tieba => home.resolve('f').replace(queryParameters: {'kw': query}),
  };
}
