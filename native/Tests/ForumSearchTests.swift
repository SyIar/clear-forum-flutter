import Foundation
import XCTest
@testable import ForumCore

final class ForumSearchTests: XCTestCase {
  private let resultURL = URL(string: "https://simpcity.cr/search/123/?q=sample&o=date")!
  private let form = #"<html data-template="search_form"><form action="/search/search" method="post"><input type="hidden" name="_xfToken" value="sample&amp;token"><input type="search" name="keywords"><input type="hidden" name="search_type" value=""></form></html>"#

  func testSearchKeepsDistinctPostMatchesAndPagination() throws {
    let source = #"""
    <html data-template="search_results"><h1 class="p-title-value">Search results</h1>
    <li class="block-row"><div class="contentRow"><div class="structItem-cell--icon"><img src="/cover.jpg"></div>
    <h3 class="contentRow-title"><a href="/threads/example.12/post-101"><span class="label">Topic</span><span class="label-append"> </span>Example</a></h3>
    <div class="contentRow-snippet">First <em>sample</em> match</div><div class="contentRow-minor">Member A - Post #3</div></div></li>
    <li class="block-row"><div class="contentRow"><h3 class="contentRow-title"><a href="/threads/example.12/post-102">Example</a></h3>
    <div class="contentRow-snippet">Second sample match</div></div></li>
    <a class="pageNav-jump--next" href="/search/123/?page=2&amp;q=sample&amp;o=date">Next</a>
    <li class="pageNav-page--current">1</li><li class="pageNav-page"><a href="/search/123/?page=5&amp;q=sample&amp;o=date">5</a></li>
    </html>
    """#
    let page = try ForumParser().parse(source, url: resultURL)
    XCTAssertEqual(page.kind, .threads)
    XCTAssertEqual(page.entries.count, 2)
    XCTAssertEqual(page.entries[0].title, "Example")
    XCTAssertEqual(page.entries[0].url.absoluteString, "https://simpcity.cr/posts/101/")
    XCTAssertEqual(page.entries[1].url.absoluteString, "https://simpcity.cr/posts/102/")
    XCTAssertEqual(page.entries[0].excerpt, "First sample match")
    XCTAssertEqual(page.entries[0].subtitle, "Member A - Post #3")
    XCTAssertEqual(page.entries[0].thumbnail?.path, "/cover.jpg")
    XCTAssertEqual(page.pageCount, 5)
    XCTAssertEqual(SitePolicy.pageNumber(page.next!), 2)
    XCTAssertEqual(SitePolicy.pageCacheKey(page.next!), SitePolicy.pageCacheKey(page.url(forPage: 2)!))
    let items = URLComponents(url: page.url(forPage: 5)!, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertTrue(items.contains(URLQueryItem(name: "q", value: "sample")))
    XCTAssertTrue(items.contains(URLQueryItem(name: "o", value: "date")))
    XCTAssertEqual(SitePolicy.pageRoot(page.next!), SitePolicy.pageRoot(resultURL))
  }

  func testCapturedSearchResultStructureWithSyntheticContent() throws {
    // Structure from a user-supplied successful result page. Content, identifiers,
    // account fields, query, and image addresses are synthetic.
    let rows = [101, 102].map { number in
      """
      <li class="block-row block-row--separated"><div class="contentRow ">
        <div class="structItem-cell structItem-cell--icon"><div class="structItem-iconContainer">
          <a href="/threads/example.12/" class="avatar dcThumbnail"><img style="background-image: url(https://images.example/cover.jpg); background-size: cover" src="data:image/png;base64,placeholder" alt="Cover"></a>
        </div></div>
        <div class="contentRow-main"><h3 class="contentRow-title"><a href="/threads/example.12/post-\(number)">
          <span class="label label--sample">Category</span><span class="label-append"> </span>
          <span class="label label--another">Another</span><span class="label-append"> </span>
          Example <em class="textHighlight">sample</em> title
        </a></h3><div class="contentRow-snippet">Matching sample text</div>
        <div class="contentRow-minor contentRow-minor--hideLinks"><ul class="listInline listInline--bullet">
          <li><a class="username" href="/members/example.7/">Example member</a></li>
          <li>Post #3</li><li><time class="u-dt" datetime="2026-01-01T00:00:00Z">Jan 1, 2026</time></li>
          <li><a href="/forums/example.48/">Example forum</a></li>
        </ul></div></div>
      </div></li>
      """
    }.joined()
    let source = """
    <html data-template="search_results" data-logged-in="true"><h1 class="p-title-value">Search results</h1>
    <div class="p-body-pageContent"><div class="block"><div class="block-container"><ol class="block-body">\(rows)</ol></div></div>
    <div class="pageNavWrapper pageNavWrapper--mixed"><div class="pageNav"><ul class="pageNav-main">
      <li class="pageNav-page pageNav-page--current"><a href="/search/123/?q=sample&amp;o=date">1</a></li>
      <li class="pageNav-page pageNav-page--later"><a href="/search/123/?page=2&amp;q=sample&amp;o=date">2</a></li>
      <li class="pageNav-page"><a href="/search/123/?page=3&amp;q=sample&amp;o=date">3</a></li></ul>
      <a class="pageNav-jump pageNav-jump--next" href="/search/123/?page=2&amp;q=sample&amp;o=date">Next</a>
    </div><div class="pageNavSimple">
      <a class="pageNavSimple-el pageNavSimple-el--current">1 of 3</a>
      <a class="pageNavSimple-el pageNavSimple-el--next" href="/search/123/?page=2&amp;q=sample&amp;o=date">Next</a>
      <a class="pageNavSimple-el pageNavSimple-el--last" href="/search/123/?page=3&amp;q=sample&amp;o=date">Last</a>
    </div></div></div></html>
    """
    let page = try SimpSearch.parseResult(source, url: resultURL, status: 200)
    XCTAssertEqual(page.entries.count, 2)
    XCTAssertEqual(page.entries.map(\.url.path), ["/posts/101/", "/posts/102/"])
    XCTAssertEqual(page.entries.first?.title, "Example sample title")
    XCTAssertEqual(page.entries.first?.excerpt, "Matching sample text")
    XCTAssertEqual(page.entries.first?.thumbnail?.absoluteString, "https://images.example/cover.jpg")
    XCTAssertTrue(page.entries.first?.subtitle.contains("Example member") == true)
    XCTAssertTrue(page.entries.first?.subtitle.contains("Example forum") == true)
    XCTAssertEqual(page.pageCount, 3)
    XCTAssertEqual(page.pageNumber, 1)
    XCTAssertEqual(page.loggedIn, true)
    let next = try XCTUnwrap(page.next)
    XCTAssertEqual(SimpSitePolicy.pageNumber(next), 2)
    XCTAssertEqual(try SimpSearch.request(url: next, userAgent: "test", cookies: []).url, next)
    XCTAssertEqual(SimpSitePolicy.pageCacheKey(try XCTUnwrap(page.url(forPage: 3))), SimpSitePolicy.pageCacheKey(try XCTUnwrap(page.lastPage)))
  }

  func testFormUsesLiveTokenAndEncodesLiteralInput() throws {
    let query = SimpSearchQuery(keywords: "  A+B & \u{96E8}  ", titlesOnly: true, order: "relevance")
    let data = try SimpSearch.formBody(form, url: SimpSearch.formURL, status: 200, query: query)
    let body = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(body.contains("_xfToken=sample%26token"))
    XCTAssertTrue(body.contains("keywords=A%2BB%20%26%20%E9%9B%A8"))
    XCTAssertTrue(body.contains("c%5Btitle_only%5D=1"))
    XCTAssertTrue(body.contains("order=relevance"))
    XCTAssertTrue(body.contains("search_type="))
    let request = try SimpSearch.request(url: SimpSearch.submitURL, body: data, userAgent: "test", cookies: [])
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://simpcity.cr")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), SimpSearch.formURL.absoluteString)
    XCTAssertEqual(request.httpBody, data)
    XCTAssertFalse(request.httpShouldHandleCookies)
  }

  func testSearchFetchesTheFormBeforeSubmittingToADifferentEndpoint() throws {
    XCTAssertEqual(SimpSearch.formURL.absoluteString, "https://simpcity.cr/search/")
    XCTAssertEqual(SimpSearch.submitURL.absoluteString, "https://simpcity.cr/search/search")
    XCTAssertEqual(ForumSite.simp.search, SimpSearch.formURL)
    let formRequest = try SimpSearch.request(url: SimpSearch.formURL, userAgent: "test", cookies: [])
    XCTAssertEqual(formRequest.httpMethod, "GET")
    XCTAssertNil(formRequest.httpBody)
    let data = try SimpSearch.formBody(form, url: SimpSearch.formURL, status: 200, query: SimpSearchQuery(keywords: "sample123"))
    let submission = try SimpSearch.request(url: SimpSearch.submitURL, body: data, userAgent: "test", cookies: [])
    XCTAssertEqual(submission.httpMethod, "POST")
    XCTAssertEqual(submission.url, SimpSearch.submitURL)
    XCTAssertTrue(String(decoding: submission.httpBody!, as: UTF8.self).contains("keywords=sample123"))
    XCTAssertThrowsError(try SimpSearch.request(url: SimpSearch.submitURL, userAgent: "test", cookies: []))
    XCTAssertThrowsError(try SimpSearch.request(url: SimpSearch.formURL, body: data, userAgent: "test", cookies: []))
    XCTAssertThrowsError(try SimpSearch.formBody(form, url: SimpSearch.submitURL, status: 200, query: SimpSearchQuery(keywords: "sample123")))
    for address in ["https://simpcity.cr/search", "https://simpcity.cr/search/"] {
      XCTAssertNoThrow(try SimpSearch.request(url: URL(string: address)!, userAgent: "test", cookies: []))
    }
    for address in ["https://simpcity.cr/search/?delete=1", "https://simpcity.cr/search/#form", "https://other.example/search/", "https://simpcity.cr:8443/search/"] {
      XCTAssertThrowsError(try SimpSearch.request(url: URL(string: address)!, userAgent: "test", cookies: []))
    }
  }

  func testSearchUsesTheMainFormWithItsLiveToken() throws {
    let source = #"""
    <html data-template="search_form"><body>
    <form action="/search/search" method="post" class="menu-content" data-xf-init="quick-search">
      <input type="hidden" name="_xfToken" value="header-token"><input type="search" name="keywords">
      <button name="from_search_menu" value="1">Advanced search</button>
    </form>
    <div class="p-body-pageContent"><form action="search" method="post" class="block" data-xf-init="ajax-submit">
      <input type="hidden" name="_xfToken" value="main-token"><input type="text" name="keywords">
      <input type="checkbox" name="c[title_only]" value="1"><input type="text" name="c[users]">
      <input type="radio" name="order" value="relevance"><input type="radio" name="order" value="date" checked>
      <input type="hidden" name="search_type" value="">
    </form></div></body></html>
    """#
    let body = try SimpSearch.formBody(source, url: SimpSearch.formURL, status: 200, query: SimpSearchQuery(keywords: "sample"))
    let encoded = String(decoding: body, as: UTF8.self)
    XCTAssertTrue(encoded.contains("_xfToken=main-token"))
    XCTAssertFalse(encoded.contains("header-token"))
    for invalid in [
      form.replacingOccurrences(of: "name=\"keywords\"", with: "name=\"keywords\" disabled"),
      form.replacingOccurrences(of: "name=\"_xfToken\"", with: "name=\"_xfToken\" disabled"),
      form.replacingOccurrences(of: "</form>", with: "<input type='hidden' name='_xfToken' value='duplicate'></form>"),
      form.replacingOccurrences(of: "</form>", with: "<input type='hidden' name='search_type' value='duplicate'></form>")
    ] {
      XCTAssertThrowsError(try SimpSearch.formBody(invalid, url: SimpSearch.formURL, status: 200, query: SimpSearchQuery(keywords: "sample")))
    }
  }

  func testSubmissionErrorExcludesInstallAndJavaScriptBoilerplate() throws {
    let source = #"""
    <html data-template="error"><body>
    <div class="block-body"><div class="block-row">Install the app</div></div>
    <noscript><div class="blockMessage">JavaScript is disabled</div></noscript>
    <div class="p-body-pageContent"><div class="blockMessage">Please specify a search query or the name of a member.</div></div>
    </body></html>
    """#
    for status in [200, 400] {
      XCTAssertThrowsError(try SimpSearch.parseResult(source, url: SimpSearch.submitURL, status: status)) {
        XCTAssertEqual(($0 as? ForumSearchNotice)?.message, "Please specify a search query or the name of a member.")
      }
    }
    XCTAssertThrowsError(try SimpSearch.parseResult(form, url: SimpSearch.submitURL, status: 200)) {
      XCTAssertEqual($0 as? ReaderFailure, .unsupported)
    }
    let empty = #"<html data-template="search_results"><div class="blockMessage">No results found.</div></html>"#
    XCTAssertTrue(try SimpSearch.parseResult(empty, url: resultURL, status: 200).entries.isEmpty)
    XCTAssertThrowsError(try SimpSearch.parseResult(empty, url: URL(string: "https://other.example/search/123/")!, status: 200))
  }

  func testSearchRejectsUnsafeRoutesAndRepeatedKeys() {
    for address in [
      "https://simpcity.cr/search/123/?page=2&page=3",
      "https://simpcity.cr/search/123/?q=sample&delete=1",
      "https://simpcity.cr/search/123/?q=sample&o=unknown",
      "https://simpcity.cr/search/123/?page=0",
      "https://simpcity.cr/search/123/?searchform=1",
      "https://simpcity.cr/search/search",
      "https://other.example/search/123/?q=sample",
      "http://simpcity.cr/search/123/?q=sample"
    ] { XCTAssertFalse(SimpSitePolicy.readable(URL(string: address)!), address) }
    XCTAssertTrue(SimpSitePolicy.readable(URL(string: "https://simpcity.cr/search/123/?q=a%2Bb&o=date&c%5Btitle_only%5D=1")!))
    XCTAssertNotEqual(SitePolicy.pageCacheKey(resultURL), SitePolicy.pageCacheKey(URL(string: "https://simpcity.cr/search/456/?q=sample&o=date")!))
    XCTAssertThrowsError(try SimpSearch.request(url: resultURL, body: Data(), userAgent: "test", cookies: []))
    XCTAssertThrowsError(try SimpSearch.request(url: ForumSite.south.search, userAgent: "test", cookies: []))
  }

  func testUnsafeOrMissingFormIsRejected() throws {
    for source in [
      form.replacingOccurrences(of: "/search/search", with: "/logout/"),
      form.replacingOccurrences(of: "/search/search", with: "https://other.example/search/search"),
      form.replacingOccurrences(of: "method=\"post\"", with: "method=\"get\""),
      form.replacingOccurrences(of: "sample&amp;token", with: ""),
      "<html><h1>Unexpected page</h1></html>"
    ] {
      XCTAssertThrowsError(try SimpSearch.formBody(source, url: SimpSearch.formURL, status: 200, query: SimpSearchQuery(keywords: "sample")))
    }
  }

  func testLoginChallengeAndRateLimitAreNotEmptyResults() {
    let query = SimpSearchQuery(keywords: "sample")
    XCTAssertThrowsError(try SimpSearch.formBody("<html data-template='login'></html>", url: SimpSearch.formURL, status: 200, query: query)) {
      XCTAssertEqual($0 as? ReaderFailure, .login)
    }
    XCTAssertThrowsError(try SimpSearch.formBody("<title>Just a moment</title>", url: SimpSearch.formURL, status: 200, query: query)) {
      XCTAssertEqual($0 as? ReaderFailure, .verification)
    }
    XCTAssertThrowsError(try ForumParser().parse("", url: resultURL, status: 429)) {
      XCTAssertEqual($0 as? ReaderFailure, .rateLimit)
    }
  }

  func testNoResultsAndServerNotice() throws {
    let empty = #"<html data-template="search_results"><div class="blockMessage">No results found.</div></html>"#
    XCTAssertTrue(try ForumParser().parse(empty, url: resultURL).entries.isEmpty)
    let notice = #"<html data-template="error"><div class="blockMessage blockMessage--error">Wait <b>20</b> seconds before searching again.</div></html>"#
    XCTAssertThrowsError(try SimpSearch.formBody(notice, url: SimpSearch.formURL, status: 200, query: SimpSearchQuery(keywords: "sample"))) {
      XCTAssertEqual(($0 as? ForumSearchNotice)?.message, "Wait 20 seconds before searching again.")
    }
    XCTAssertThrowsError(try ForumParser().parse(#"<html data-template="search_results"></html>"#, url: resultURL))
  }

  func testPostRedirectPreservesTheMatchedReplyAnchor() throws {
    let post = URL(string: "https://simpcity.cr/posts/101/")!
    let redirected = try XCTUnwrap(ForumRequest.redirect("/threads/topic.12/page-4#post-101", from: post))
    XCTAssertEqual(redirected.fragment, "post-101")
    XCTAssertEqual(SitePolicy.pageNumber(redirected), 4)
    let canonical = try XCTUnwrap(ForumRequest.redirect("/threads/renamed.12/page-4", from: redirected))
    XCTAssertEqual(canonical.fragment, "post-101")
    XCTAssertEqual(ForumRequest.redirect("/threads/topic.12/#post-102", from: canonical)?.fragment, "post-102")
    let request = try ForumRequest.page(site: .simp, url: canonical, userAgent: "test", cookies: [])
    XCTAssertNil(request.url?.fragment)
    XCTAssertTrue(SimpSitePolicy.readable(canonical))
  }

  func testSearchCookiesStayOnTheSimpOriginAndMatchingPath() throws {
    func cookie(_ name: String, domain: String, path: String = "/") -> HTTPCookie {
      HTTPCookie(properties: [.name: name, .value: "test", .domain: domain, .path: path, .secure: "TRUE"])!
    }
    let cookies = [cookie("session", domain: "simpcity.cr"), cookie("south", domain: "south-plus.net"),
                   cookie("private", domain: "simpcity.cr", path: "/account")]
    let request = try SimpSearch.request(url: resultURL, userAgent: "test", cookies: cookies)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=test")
    XCTAssertNil(request.httpBody)
    XCTAssertEqual(request.httpMethod, "GET")
    let foreign = URL(string: "https://other.example/threads/topic.12/post-101")!
    XCTAssertNil(SimpSitePolicy.resolve(foreign.absoluteString, from: resultURL, internalOnly: true))
    XCTAssertNil(SimpSitePolicy.resolve("/threads/topic.12/post-101?delete=1", from: resultURL, internalOnly: true))
  }
}
