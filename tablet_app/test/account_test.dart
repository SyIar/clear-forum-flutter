import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/account.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/parsers.dart';
import 'package:forum_tablet/session.dart';
import 'package:forum_tablet/site.dart';

void main() {
  const simp = ForumSite(Module.simp);
  const south = ForumSite(Module.south);

  test('Each authenticated forum opens its real sign-in endpoint', () {
    expect(simp.login.toString(), 'https://simpcity.cr/login/');
    expect(south.login.toString(), 'https://south-plus.net/login.php');
    expect(const ForumSite(Module.bookhouse).supportsLogin, isFalse);
  });

  test('Simp identifies only the account header, not a post author', () {
    final account = ForumAccount.inspect(
      simp,
      simp.home,
      '<html data-logged-in="true"><a class="p-navgroup-link--user">'
      '<span class="p-navgroup-linkText">Reader</span></a>'
      '<article><a class="username">Someone else</a></article></html>',
    );
    expect(account.signedIn, isTrue);
    expect(account.name, 'Reader');
    expect(
      ForumAccount.inspect(
        simp,
        simp.home,
        '<html data-logged-in="false"><a class="username">Post author</a></html>',
      ).status,
      AccountStatus.guest,
    );
    expect(
      ForumAccount.inspect(
        simp,
        Uri.parse('https://example.org/'),
        '<html data-logged-in="true">',
      ).status,
      AccountStatus.unknown,
    );
  });

  test('South recognizes normal and rewritten sign-out links', () {
    for (final logout in [
      'login.php?action=quit',
      'login.php?action-quit-verify-abc.html',
    ]) {
      final account = ForumAccount.inspect(
        south,
        south.home,
        '<div id="user_info"><a href="u.php?uid=123">Reader</a>'
        '<a href="$logout">Sign out</a></div>',
      );
      expect(account.signedIn, isTrue);
      expect(account.name, 'Reader');
    }
  });

  test('South ignores quoted and off-site sign-out links', () {
    final account = ForumAccount.inspect(
      south,
      south.home,
      '<article class="js-post"><a href="login.php?action=quit">Quote</a></article>'
      '<a href="https://example.org/login.php?action=quit">Unrelated</a>'
      '<form action="login.php"><input type="password" name="pwpwd"></form>',
    );
    expect(account.status, AccountStatus.guest);
  });

  test('A verification document does not erase the last observed account', () {
    final session = ForumSession(simp);
    session.observeAccount(simp.home, '<html data-logged-in="true">');
    session.observeAccount(
      simp.home,
      '<title>DDoS-Guard</title><h1>Checking your browser</h1>',
    );
    expect(session.account.value.signedIn, isTrue);
    session.observeAccount(simp.home, '<html data-logged-in="false">');
    expect(session.account.value.status, AccountStatus.guest);
  });

  test('An older background request cannot overwrite a completed sign-in', () {
    final session = ForumSession(simp);
    session.authenticationBoundary();
    session.observeAccount(simp.home, '<html data-logged-in="true">');
    session.observeAccount(
      simp.home,
      '<html data-logged-in="false">',
      revision: 0,
    );
    expect(session.account.value.signedIn, isTrue);
  });

  test('South gated content reports sign-in instead of unsupported page', () {
    expect(
      () => PageParser(south).parse(
        '<form action="login.php"><input type="password" name="pwpwd"></form>',
        south.home.resolve('/thread.php?fid=9'),
      ),
      throwsA(
        isA<ReaderFailure>().having(
          (error) => error.kind,
          'kind',
          FailureKind.login,
        ),
      ),
    );
  });
}
