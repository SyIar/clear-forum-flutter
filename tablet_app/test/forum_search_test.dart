import 'package:flutter_test/flutter_test.dart';
import 'package:forum_tablet/forum_search.dart';
import 'package:forum_tablet/models.dart';
import 'package:forum_tablet/parsers.dart';
import 'package:forum_tablet/site.dart';

void main() {
  const simp = ForumSite(Module.simp), south = ForumSite(Module.south);
  const simpForm =
      '<form method="post" action="/search/search"><input name="keywords">'
      '<input type="hidden" name="_xfToken" value="fresh-token"><input type="hidden" name="search_type" value="post"></form>';
  test('Simp submits only the validated search form with its fresh token', () {
    final submission = ForumSearch.submission(
      simp,
      simpForm,
      ForumSearch.formUrl(simp),
      const SearchQuery('two words', titlesOnly: true),
    );
    expect(submission.url.path, '/search/search');
    expect(submission.fields, {
      '_xfToken': 'fresh-token',
      'keywords': 'two words',
      'order': 'date',
      'search_type': 'post',
      'c[title_only]': '1',
    });
    expect(
      () => ForumSearch.submission(
        simp,
        simpForm.replaceAll('/search/search', 'https://example.org/search'),
        ForumSearch.formUrl(simp),
        const SearchQuery('test'),
      ),
      throwsA(isA<ReaderFailure>()),
    );
    expect(
      () => ForumSearch.submission(
        simp,
        simpForm.replaceAll('fresh-token', ''),
        ForumSearch.formUrl(simp),
        const SearchQuery('test'),
      ),
      throwsA(isA<ReaderFailure>()),
    );
  });
  test('Simp search result paging retains the search ID and query options', () {
    final url = simp.home.resolve(
      '/search/123/?q=test&o=date&c%5Btitle_only%5D=1',
    );
    final page = PageParser(simp).parse(
      '<html data-template="search_results"><h1 class="p-title-value">Results</h1>'
      '<div class="block-row"><div class="contentRow"><h3 class="contentRow-title"><a href="/threads/topic.20/">Topic</a></h3></div></div>'
      '<div class="pageNav-page"><a href="?q=test&o=date&c%5Btitle_only%5D=1&page=2">2</a></div></html>',
      url,
    );
    expect(simp.readable(url), isTrue);
    expect(page.entries.single.title, 'Topic');
    expect(page.next!.queryParameters['page'], '2');
    expect(page.next!.queryParameters['c[title_only]'], '1');
  });
  test('South form preserves hidden fields and validates available search options', () {
    const source =
        '<form name="sF" method="POST" action="search.php"><input type="hidden" name="step" value="2">'
        '<input type="hidden" name="verify" value="token"><input name="keyword">'
        '<input name="method" value="OR"><input name="sch_area" value="0"><input name="asc" value="DESC">'
        '<select name="f_fid"><option value="all"></option></select><select name="sch_time"><option value="31536000"></option></select>'
        '<select name="orderway"><option value="postdate"></option></select></form>';
    final submission = ForumSearch.submission(
      south,
      source,
      ForumSearch.formUrl(south),
      const SearchQuery('words'),
    );
    expect(submission.fields['step'], '2');
    expect(submission.fields['verify'], 'token');
    expect(submission.fields['keyword'], 'words');
    expect(
      () => ForumSearch.submission(
        south,
        source.replaceAll('value="OR"', 'value="AND"'),
        ForumSearch.formUrl(south),
        const SearchQuery('words'),
      ),
      throwsA(isA<ReaderFailure>()),
    );
  });
  test('South result pages resolve highlighted thread links and keep search identity', () {
    final url = south.home.resolve(
      '/search.php?step-2-keyword-words-sid-123-seekfid-all-page-1.html',
    );
    final source =
        '<div id="main"><div class="t"><table><tr class="tr2">${'<td>Heading</td>' * 7}</tr>'
        '<tr class="tr3"><th><a href="read.php?tid-20-keyword-words.html">Result</a></th><td><a href="u.php?action-show-uid-42.html">Writer</a></td></tr></table></div></div>'
        '<div class="pages"><a href="search.php?step-2-keyword-words-sid-123-seekfid-all-page-2.html">2</a></div>';
    final page = PageParser(south).parse(source, url);
    expect(south.readable(url), isTrue);
    expect(page.entries.single.url.queryParameters['tid'], '20');
    expect(page.entries.single.authorID, '42');
    expect(south.readable(page.next!), isTrue);
    expect(page.next!.queryParameters['sid'], '123');
    expect(south.pageNumber(page.next!), 2);
    expect(
      south.readable(
        south.home.resolve(
          '/search.php?step=2&keyword=x&sid=123&seekfid=all&action=delete',
        ),
      ),
      isFalse,
    );
  });
}
