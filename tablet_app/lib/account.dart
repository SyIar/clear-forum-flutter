import 'package:html/parser.dart' as html;

import 'site.dart';

enum AccountStatus { unknown, guest, signedIn }

class ForumAccount {
  const ForumAccount(this.status, {this.name = ''});
  final AccountStatus status;
  final String name;
  bool get signedIn => status == AccountStatus.signedIn;

  static ForumAccount inspect(ForumSite site, Uri url, String source) {
    const unknown = ForumAccount(AccountStatus.unknown);
    const guest = ForumAccount(AccountStatus.guest);
    if (!site.supportsLogin || !site.sameOrigin(url)) return unknown;
    final doc = html.parse(source);
    if (site.module == Module.simp) {
      final state = doc.documentElement?.attributes['data-logged-in'];
      if (state == 'false') return guest;
      if (state != 'true') return unknown;
      final name =
          doc
              .querySelector(
                '.p-navgroup-link--user .p-navgroup-linkText, '
                '.p-navgroup-link--user .username, .p-navgroup-link--user',
              )
              ?.text
              .trim() ??
          '';
      return ForumAccount(AccountStatus.signedIn, name: name);
    }
    // Quoted links or login forms in posts are not account evidence.
    for (final post in doc.querySelectorAll(
      '.js-post,.tpc_content,[data-post-body]',
    )) {
      post.remove();
    }
    final logout = doc.querySelectorAll('a[href]').any((a) {
      final target = Uri.tryParse(a.attributes['href'] ?? '');
      if (target == null) return false;
      final resolved = url.resolveUri(target);
      return site.sameOrigin(resolved) &&
          resolved.path == '/login.php' &&
          (const [
                'quit',
                'logout',
              ].contains(resolved.queryParameters['action']) ||
              RegExp(r'^action-(?:quit|logout)(?:-|\.html|$)')
                  .hasMatch(resolved.query));
    });
    if (logout) {
      final name =
          doc
              .querySelector(
                '#user_info a[href*="u.php"],#user-login a[href*="u.php"],'
                '#user_info .username,#user-login .username',
              )
              ?.text
              .trim() ??
          '';
      return ForumAccount(AccountStatus.signedIn, name: name);
    }
    if (doc.querySelector(
          'form[action*="login"] input[type="password"],'
          'form input[name="pwpwd"],#user-login a[href="login.php"]',
        ) !=
        null) {
      return guest;
    }
    return unknown;
  }
}
