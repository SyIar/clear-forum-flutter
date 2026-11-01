import 'site.dart';

extension ForumIdentity on ForumSite {
  Map<String, String> parameters(Uri url) {
    if (url.query.contains('=')) return url.queryParameters;
    return {
      for (final match in RegExp(
        r'(tid|fid|uid|page|type|action)-([A-Za-z0-9_]+)',
      ).allMatches(url.query.replaceFirst(RegExp(r'\.html$'), '')))
        match[1]!: match[2]!,
    };
  }

  String? threadKey(Uri url) {
    if (!sameOrigin(url)) return null;
    final id = switch (module) {
      Module.simp => RegExp(
        r'^/threads/[^/]+\.(\d+)(?:/|$)',
      ).firstMatch(url.path)?[1],
      Module.south => url.path == '/read.php' ? parameters(url)['tid'] : null,
      Module.bookhouse =>
        url.queryParameters['act'] == 'threadview'
            ? url.queryParameters['tid']
            : null,
      Module.tieba => RegExp(r'^/p/(\d+)').firstMatch(url.path)?[1],
    };
    return id == null ? null : '${module.name}:$id';
  }

  Uri? threadRoot(Uri url) {
    final key = threadKey(url);
    if (key == null) return null;
    if (module == Module.south) {
      return home
          .resolve('/read.php')
          .replace(queryParameters: {'tid': key.split(':').last});
    }
    return pageUrl(url, 1).removeFragment();
  }

  bool sameThread(Uri a, Uri b) =>
      threadKey(a) != null && threadKey(a) == threadKey(b);
  bool filtered(Uri url) =>
      parameters(url).containsKey('uid') ||
      url.queryParameters.containsKey('order');

  Uri? authorTopics(String id) => module == Module.south && validAuthor(id)
      ? home.resolve('/u.php?action-topic-uid-$id.html')
      : null;
  Uri? authorProfile(String id) => module == Module.south && validAuthor(id)
      ? home.resolve('/u.php?uid=$id')
      : null;
  Uri? onlyAuthor(Uri url, String id) =>
      module == Module.south && validAuthor(id) && threadKey(url) != null
      ? home.resolve('/read.php?tid-${parameters(url)['tid']}-uid-$id.html')
      : null;
  bool validAuthor(String id) => RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(id);
}
