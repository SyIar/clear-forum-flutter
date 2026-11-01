import 'package:app_links/app_links.dart';

enum TiebaLinkKind {
  thread,
  forum,
  user,
  notifications,
  history,
  favorites,
  search,
}

class TiebaLink {
  const TiebaLink({
    required this.kind,
    this.value = '',
    this.postId = '',
    this.page = 1,
  });
  final TiebaLinkKind kind;
  final String value, postId;
  final int page;

  static TiebaLink? parse(Uri uri) {
    final query = uri.queryParameters;
    final page = (int.tryParse(query['pn'] ?? '') ?? 1).clamp(1, 1000000);
    final postId = _numeric(query['pid']) ?? '';
    if (uri.scheme == 'tblite') {
      if (uri.pathSegments.length > 1 || uri.userInfo.isNotEmpty) return null;
      final value = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
      return switch (uri.host.toLowerCase()) {
        'thread' when _numeric(value) != null => TiebaLink(
          kind: TiebaLinkKind.thread,
          value: value,
          postId: postId,
          page: page,
        ),
        'forum' when value.isNotEmpty => TiebaLink(
          kind: TiebaLinkKind.forum,
          value: value,
        ),
        'user' when _numeric(value) != null => TiebaLink(
          kind: TiebaLinkKind.user,
          value: value,
        ),
        'notifications' => TiebaLink(
          kind: TiebaLinkKind.notifications,
          value: value,
        ),
        'history' => const TiebaLink(kind: TiebaLinkKind.history),
        'favorite' ||
        'favorites' => const TiebaLink(kind: TiebaLinkKind.favorites),
        'search' => TiebaLink(
          kind: TiebaLinkKind.search,
          value: query['word'] ?? '',
        ),
        _ => null,
      };
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (!{
      'tieba.baidu.com',
      'tiebac.baidu.com',
      'www.tieba.com',
    }.contains(uri.host.toLowerCase())) {
      return null;
    }
    final parts = uri.pathSegments;
    if (parts.length >= 2 && parts.first == 'p' && _numeric(parts[1]) != null) {
      return TiebaLink(
        kind: TiebaLinkKind.thread,
        value: parts[1],
        postId: postId,
        page: page,
      );
    }
    final threadId = _numeric(query['kz']) ?? _numeric(query['tid']);
    if (threadId != null && {'/mo/q/m', '/p', '/mo/q/p'}.contains(uri.path)) {
      return TiebaLink(
        kind: TiebaLinkKind.thread,
        value: threadId,
        postId: postId,
        page: page,
      );
    }
    final forum = query['kw'] ?? query['word'];
    if (forum != null &&
        forum.isNotEmpty &&
        {'/f', '/f/', '/mo/q/f'}.contains(uri.path)) {
      return TiebaLink(kind: TiebaLinkKind.forum, value: forum);
    }
    return null;
  }

  static String? _numeric(String? value) =>
      value != null && RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(value)
      ? value
      : null;
}

/// Instantiate before runApp and subscribe after the navigator is ready.
class DeepLinks {
  DeepLinks({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();
  final AppLinks _appLinks;

  /// Includes the initial link as well as links received while running.
  Stream<TiebaLink> get links => _appLinks.uriLinkStream
      .map(TiebaLink.parse)
      .where((link) => link != null)
      .cast<TiebaLink>();
}
