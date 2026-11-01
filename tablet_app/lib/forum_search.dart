import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'models.dart';
import 'site.dart';

class SearchQuery {
  const SearchQuery(
    this.keywords, {
    this.titlesOnly = false,
    this.order = 'date',
  });
  final String keywords, order;
  final bool titlesOnly;
}

class SearchNotice implements Exception {
  const SearchNotice(this.message);
  final String message;
}

class SearchSubmission {
  const SearchSubmission(this.url, this.fields);
  final Uri url;
  final Map<String, String> fields;
  // Values are JSON strings assigned to DOM properties, never HTML fragments.
  String get script =>
      '''(() => {
    const form = document.createElement('form');
    form.method = 'POST'; form.action = ${jsonEncode('$url')};
    for (const [name, value] of Object.entries(${jsonEncode(fields)})) {
      const input = document.createElement('input');
      input.type = 'hidden'; input.name = name; input.value = value;
      form.appendChild(input);
    }
    document.body.appendChild(form);
    HTMLFormElement.prototype.submit.call(form);
  })();''';
}

class ForumSearch {
  static Uri formUrl(ForumSite site) => site.home.resolve(
    site.module == Module.simp ? '/search/' : '/search.php',
  );
  static void validate(Document doc, ForumSite site, Uri url) {
    final title = doc.querySelector('title')?.text.toLowerCase() ?? '';
    if (doc.querySelector('#challenge-running,#challenge-form') != null ||
        title.contains('just a moment') ||
        title.contains('ddos-guard')) {
      throw const ReaderFailure(FailureKind.verification);
    }
    if (site.isLogin(url) ||
        doc.querySelector(
              'form[action*="login"] input[type="password"],input[name="pwpwd"]',
            ) !=
            null) {
      throw const ReaderFailure(FailureKind.login);
    }
    final notice = doc.querySelector('.blockMessage--error')?.text.trim();
    if (notice != null && notice.isNotEmpty) {
      throw SearchNotice(
        notice.length > 600 ? notice.substring(0, 600) : notice,
      );
    }
  }

  static SearchSubmission submission(
    ForumSite site,
    String source,
    Uri url,
    SearchQuery query,
  ) {
    if ((!([
              formUrl(site).path,
              if (site.module == Module.simp) '/search',
            ].contains(url.path)) ||
            url.hasQuery) ||
        !site.sameOrigin(url)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final doc = html.parse(source);
    validate(doc, site, url);
    final keywords = query.keywords.trim();
    if (keywords.isEmpty || utf8.encode(keywords).length > 1024) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final action = site.module == Module.simp
        ? url.resolve('/search/search')
        : url;
    Element? form;
    for (final candidate in doc.querySelectorAll('form')) {
      if (candidate.attributes['method']?.toLowerCase() == 'post' &&
          site.resolve(candidate.attributes['action'], url) == action &&
          candidate.querySelector(
                'input[name="${site.module == Module.simp ? 'keywords' : 'keyword'}"]:not([disabled])',
              ) !=
              null) {
        form = candidate;
        break;
      }
    }
    if (form == null) throw const ReaderFailure(FailureKind.unsupported);
    if (site.module == Module.simp) {
      final tokens = form.querySelectorAll(
        'input[type="hidden"][name="_xfToken"]:not([disabled])',
      );
      final types = form.querySelectorAll(
        'input[type="hidden"][name="search_type"]:not([disabled])',
      );
      if (tokens.length != 1 ||
          (tokens.single.attributes['value'] ?? '').isEmpty ||
          types.length > 1 ||
          !['date', 'relevance'].contains(query.order)) {
        throw const ReaderFailure(FailureKind.unsupported);
      }
      return SearchSubmission(action, {
        '_xfToken': tokens.single.attributes['value']!,
        'keywords': keywords,
        'order': query.order,
        'search_type': types.firstOrNull?.attributes['value'] ?? '',
        if (query.titlesOnly) 'c[title_only]': '1',
      });
    }
    if (site.module != Module.south ||
        utf8.encode(keywords).length < 2 ||
        form.attributes['name'] != 'sF' ||
        form.querySelector('input[name="step"][value="2"]') == null) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final selected = {
      'method': 'OR',
      'sch_area': '0',
      'asc': 'DESC',
      'f_fid': 'all',
      'sch_time': '31536000',
      'orderway': 'postdate',
    };
    for (final field in selected.entries) {
      if (form.querySelector(
            'input[name="${field.key}"][value="${field.value}"]:not([disabled]),select[name="${field.key}"]:not([disabled]) option[value="${field.value}"]:not([disabled])',
          ) ==
          null) {
        throw const ReaderFailure(FailureKind.unsupported);
      }
    }
    final fields = <String, String>{};
    for (final input in form.querySelectorAll(
      'input[type="hidden"][name]:not([disabled])',
    )) {
      final name = input.attributes['name']!;
      if (fields.containsKey(name)) {
        throw const ReaderFailure(FailureKind.unsupported);
      }
      fields[name] = input.attributes['value'] ?? '';
    }
    return SearchSubmission(action, {
      ...fields,
      ...selected,
      'keyword': keywords,
      'pwuser': '',
    });
  }

  static Map<String, String>? southParameters(Uri url) {
    if (url.path != '/search.php' || url.toString().length > 8192) return null;
    Map<String, String> fields;
    if (!url.query.contains('=')) {
      final match = RegExp(
        r'^step-2-keyword-(.*)-sid-([1-9][0-9]{0,17})-seekfid-(all|[1-9][0-9]{0,17})-page-([1-9][0-9]{0,4})\.html$',
      ).firstMatch(url.query);
      if (match == null) return null;
      fields = {
        'step': '2',
        'keyword': Uri.decodeComponent(match[1]!),
        'sid': match[2]!,
        'seekfid': match[3]!,
        'page': match[4]!,
      };
    } else {
      if (url.queryParametersAll.values.any((v) => v.length != 1)) return null;
      fields = {...url.queryParameters};
    }
    final number = RegExp(r'^[1-9][0-9]{0,17}$');
    if (!fields.keys.every(
          (k) => ['step', 'keyword', 'sid', 'seekfid', 'page'].contains(k),
        ) ||
        fields['step'] != '2' ||
        fields['keyword'] == null ||
        utf8.encode(fields['keyword']!).length > 1024 ||
        !number.hasMatch(fields['sid'] ?? '') ||
        !(fields['seekfid'] == 'all' ||
            number.hasMatch(fields['seekfid'] ?? '')) ||
        !RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(fields['page'] ?? '1')) {
      return null;
    }
    return {...fields, 'page': fields['page'] ?? '1'};
  }

  static ForumPage southResult(ForumSite site, String source, Uri url) {
    if (!site.sameOrigin(url) ||
        (url != formUrl(site) && southParameters(url) == null)) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final doc = html.parse(source);
    validate(doc, site, url);
    final table = doc
        .querySelectorAll('#main .t table')
        .where((t) => t.querySelectorAll('tr.tr2 td').length == 7)
        .firstOrNull;
    if (table == null) {
      final notice = doc.querySelector('#main .t')?.text.trim() ?? '';
      if (notice.isNotEmpty && doc.querySelector('form[name="sF"]') == null) {
        throw SearchNotice(
          notice.length > 600 ? notice.substring(0, 600) : notice,
        );
      }
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final entries = <ForumEntry>[], seen = <Uri>{};
    for (final row in table.querySelectorAll('tr.tr3')) {
      final anchor = row.querySelector('th a[href]');
      var target = site.resolve(anchor?.attributes['href'], url);
      if (target == null ||
          !site.sameOrigin(target) ||
          target.path != '/read.php') {
        continue;
      }
      if (!site.readable(target)) {
        final id = RegExp(r'^tid-([1-9][0-9]{0,17})-keyword-.*\.html$')
            .firstMatch(target.query)?[1];
        if (id == null) continue;
        target = site.home.resolve('/read.php?tid=$id');
      }
      if (!seen.add(target)) continue;
      final author = row.querySelector('a[href*="u.php"]');
      entries.add(
        ForumEntry(
          title: anchor!.text.trim(),
          url: target,
          subtitle: author?.text.trim() ?? '',
          authorID:
              RegExp(r'uid[=-]([1-9][0-9]*)')
                  .firstMatch(author?.attributes['href'] ?? '')?[1] ??
              '',
        ),
      );
    }
    if (entries.isEmpty && table.querySelectorAll('tr.tr3').isNotEmpty) {
      throw const ReaderFailure(FailureKind.unsupported);
    }
    final navigation = doc
        .querySelectorAll('.pages a[href]')
        .map((a) => site.resolve(a.attributes['href'], url))
        .nonNulls
        .where((u) => site.sameOrigin(u) && southParameters(u) != null)
        .toList();
    final number =
        int.tryParse(southParameters(url)?['page'] ?? '') ??
        int.tryParse(doc.querySelector('.pages li b')?.text ?? '') ??
        1;
    final seed = southParameters(url) != null ? url : navigation.firstOrNull;
    final canonical = seed == null ? url : site.pageUrl(seed, number);
    final pages = navigation.where(
      (u) => site.pageUrl(u, 1) == site.pageUrl(canonical, 1),
    );
    final last = [
      number,
      ...pages.map(site.pageNumber),
    ].reduce((a, b) => a > b ? a : b);
    return ForumPage(
      url: canonical,
      title: 'Search results',
      kind: PageKind.threads,
      entries: entries,
      pageNumber: number,
      totalPages: last,
      previous: number > 1 ? site.pageUrl(canonical, number - 1) : null,
      next: number < last ? site.pageUrl(canonical, number + 1) : null,
    );
  }
}
