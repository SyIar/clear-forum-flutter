class ForumSite {
  static final base = Uri.parse('https://simpcity.cr/');
  static final _pagePath = RegExp(
    r'^/(?:(?:forums|threads)/[^/]+\.\d+(?:/(?:page-\d+/?)?)?|posts/\d+/?|search-forums/[^/]+(?:/(?:page-\d+/?)?)?|whats-new/(?:posts/)?|watched/threads/?)$',
  );
  static final _unreadThreadPath = RegExp(r'^(/threads/[^/]+\.\d+/)unread/?$');
  static bool sameOrigin(Uri url) =>
      url.scheme == 'https' &&
      url.host == base.host &&
      url.port == 443 &&
      url.userInfo.isEmpty;
  static bool readable(Uri url) {
    String path;
    try {
      path = Uri.decodeComponent(url.path);
    } on FormatException {
      return false;
    }
    if (!sameOrigin(url) ||
        path.contains('%') ||
        path.contains('\\') ||
        path.split('/').any((part) => part == '.' || part == '..')) {
      return false;
    }
    if (url.normalizePath().path != url.path) return false;
    if (path != '/' && !_pagePath.hasMatch(path)) return false;
    return url.queryParametersAll.entries.every(
      (entry) =>
          entry.value.length == 1 &&
          switch (entry.key) {
            'page' => RegExp(r'^[1-9]\d{0,4}$').hasMatch(entry.value.single),
            'order' => const {
              'post_date',
              'last_post_date',
              'reaction_score',
            }.contains(entry.value.single),
            _ => false,
          },
    );
  }

  static Uri? resolve(String? value, Uri page, {bool internal = false}) {
    if (value == null || value.trim().isEmpty) return null;
    final candidate = Uri.tryParse(value.trim());
    if (candidate == null) return null;
    var resolved = page.resolveUri(candidate);
    if (resolved.scheme != 'https' ||
        resolved.userInfo.isNotEmpty ||
        resolved.host.isEmpty) {
      return null;
    }
    if (sameOrigin(resolved)) {
      final unread = _unreadThreadPath.firstMatch(resolved.path);
      final query = resolved.queryParametersAll;
      if (unread != null &&
          (query.isEmpty ||
              (query.length == 1 &&
                  query['new']?.length == 1 &&
                  query['new']?.single == '1'))) {
        final canonical = base.resolve(unread.group(1)!);
        if (readable(canonical)) resolved = canonical;
      }
    }
    if (internal && !readable(resolved)) return null;
    return resolved;
  }
}
