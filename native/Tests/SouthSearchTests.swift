import Foundation
import XCTest
@testable import ForumCore

final class SouthSearchTests: XCTestCase {
  private let form = #"""
  <html><meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <form name="sF" action="search.php?" method="post"><input type="hidden" name="step" value="2">
  <input type="text" name="keyword"><input type="radio" name="method" value="OR" checked><input type="radio" name="method" value="AND">
  <input type="radio" name="sch_area" value="0" checked><input type="radio" name="sch_area" value="1" disabled>
  <select name="f_fid"><option value="all" selected>All</option></select>
  <select name="sch_time"><option value="all">All</option><option value="31536000" selected>Year</option></select>
  <select name="orderway"><option value="postdate">Date</option><option value="hits">Views</option></select>
  <input type="radio" name="asc" value="ASC" checked><input type="radio" name="asc" value="DESC" checked></form></html>
  """#
  private let results = #"""
  <div id="main"><div class="pages"><ul><li><a href="search.php?step-2-keyword-sample-key-sid-123-seekfid-all-page-1.html">First</a></li>
  <li><b>1</b></li><li><a href="search.php?step-2-keyword-sample-key-sid-123-seekfid-all-page-2.html">2</a></li>
  <li><a href="search.php?step-2-keyword-sample-key-sid-123-seekfid-all-page-10.html">Last</a></li>
  <li class="pagesone">Pages: 1/10</li></ul></div><div class="t"><table><tr><td class="h" colspan="7">Topics</td></tr>
  <tr class="tr2 tac"><td>Status</td><td>Title</td><td>Forum</td><td>Author</td><td>Replies</td><td>Views</td><td>Latest</td></tr>
  <tr class="tr3 tac"><td class="y-style">Icon</td><th class="y-style"><a href="read.php?tid-42-keyword-sample-key.html">First <font color="red"><u>sample</u></font></a></th>
  <td class="y-style"><a href="thread.php?fid-9.html">Discussion</a></td><td class="smalltxt y-style"><a href="u.php?action-show-uid-17.html">Member</a><br>2026-09-29</td>
  <td>6</td><td>99</td><td><a href="read.php?tid-42-page-e.html#a">2026-09-29 22:35</a></td></tr>
  <tr class="tr3 tac"><td>Icon</td><th><a href="read.php?tid-43-keyword-sample-key.html">Second match</a></th>
  <td>Discussion</td><td><a href="u.php?action-show-uid-18.html">Other member</a></td><td>3</td><td>10</td><td>Latest</td></tr>
  </table></div></div>
  """#

  func testPostResponseGetsStableResultURLAndThreadTargets() throws {
    let page = try ForumParser().parse(results, url: URL(string: "https://south-plus.net/search.php?")!)
    XCTAssertEqual(page.entries.count, 2)
    XCTAssertEqual(page.entries[0].title, "First sample")
    XCTAssertEqual(page.entries[0].url.absoluteString, "https://south-plus.net/read.php?tid=42")
    XCTAssertEqual(page.entries[0].authorID, "17")
    XCTAssertEqual(page.entries[0].authorName, "Member")
    XCTAssertEqual(page.entries[0].subtitle, "Discussion \u{00B7} Member 2026-09-29")
    XCTAssertEqual(page.pageNumber, 1)
    XCTAssertEqual(page.pageCount, 10)
    XCTAssertTrue(ForumSite.south.accepts(page.url))
    XCTAssertEqual(SouthSearch.parameters(page.url)?["sid"], "123")
    XCTAssertEqual(SouthSearch.parameters(page.next!)?["keyword"], "sample-key")
    XCTAssertNil(page.previous)
    XCTAssertEqual(SitePolicy.pageCacheKey(page.next!), SitePolicy.pageCacheKey(page.url(forPage: 2)!))
    var library = LibraryDocument(site: .south)
    library.blockAuthor(id: "17", name: "Member")
    XCTAssertEqual(library.visibleContent(in: page).entries.map(\.authorID), ["18"])
  }

  func testPagingPreservesUnicodePunctuationAndSearchIdentity() throws {
    let url = URL(string: "https://south-plus.net/search.php?step-2-keyword-%E9%9B%A8-A%2BB%26C-sid-123-seekfid-all-page-3.html")!
    let next = try XCTUnwrap(SitePolicy.pageURL(url, number: 4))
    XCTAssertEqual(SouthSearch.parameters(next)?["keyword"], "\u{96E8}-A+B&C")
    XCTAssertEqual(SitePolicy.pageNumber(next), 4)
    XCTAssertEqual(SitePolicy.pageRoot(url), SitePolicy.pageRoot(next))
    let alias = try XCTUnwrap(SouthSearch.pageURL(url, number: 3))
    XCTAssertEqual(SitePolicy.pageCacheKey(url), SitePolicy.pageCacheKey(alias))
    let other = URL(string: url.absoluteString.replacingOccurrences(of: "sid-123", with: "sid-456"))!
    XCTAssertNotEqual(SitePolicy.pageCacheKey(url), SitePolicy.pageCacheKey(other))
    let page = try SouthSearch.parse(results, url: alias)
    XCTAssertEqual(page.pageNumber, 3)
    XCTAssertEqual(SitePolicy.pageNumber(page.previous!), 2)
  }

  func testFormSubmissionMatchesEnabledControls() throws {
    let query = SouthSearchQuery(keywords: "\u{96E8} A+B&C", method: "AND", order: "hits", time: "all")
    let body = try SouthSearch.formBody(form, url: SouthSearch.formURL, status: 200, query: query)
    let encoded = String(decoding: body, as: UTF8.self)
    for value in ["step=2", "sch_area=0", "asc=DESC", "f_fid=all", "sch_time=all", "orderway=hits", "method=AND", "keyword=%E9%9B%A8%20A%2BB%26C"] {
      XCTAssertTrue(encoded.contains(value), value)
    }
    XCTAssertFalse(encoded.contains("sch_area=1"))
    let request = try SouthSearch.request(url: SouthSearch.formURL, body: body, userAgent: "test", cookies: [])
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.httpBody, body)
    XCTAssertFalse(request.httpShouldHandleCookies)
    XCTAssertThrowsError(try SouthSearch.formBody(form.replacingOccurrences(of: "value=\"0\" checked", with: "value=\"0\" disabled"), url: SouthSearch.formURL, status: 200, query: query))
    XCTAssertThrowsError(try SouthSearch.formBody(form.replacingOccurrences(of: "search.php?", with: "https://other.example/search.php"), url: SouthSearch.formURL, status: 200, query: query))
  }

  func testUnexpectedRoutesAndMessagesNeverBecomeEmptySuccesses() throws {
    for address in [
      "https://south-plus.net/search.php?step=2&keyword=x&sid=123&seekfid=all&delete=1",
      "https://south-plus.net/search.php?step=2&keyword=x&sid=123&seekfid=all&page=1&page=2",
      "https://south-plus.net/search.php?step-2-keyword-x-sid-123-seekfid-all-page-0.html",
      "https://other.example/search.php?step-2-keyword-x-sid-123-seekfid-all-page-1.html"
    ] { XCTAssertNil(SouthSearch.parameters(URL(string: address)!)) }
    XCTAssertNil(SouthSearch.threadURL("https://other.example/read.php?tid-42-keyword-x.html", from: SouthSearch.formURL))
    XCTAssertThrowsError(try SouthSearch.parse(form, url: SouthSearch.formURL))
    XCTAssertThrowsError(try SouthSearch.parse(results, url: SouthSearch.formURL, status: 429)) { XCTAssertEqual($0 as? ReaderFailure, .rateLimit) }
    XCTAssertThrowsError(try SouthSearch.parse("<div id='main'><div class='t'>Please wait before searching again.</div></div>", url: SouthSearch.formURL)) {
      XCTAssertEqual(($0 as? ForumSearchNotice)?.message, "Please wait before searching again.")
    }
    XCTAssertThrowsError(try SouthSearch.parse("<form action='login.php'><input type='password' name='pwpwd'></form>", url: SouthSearch.formURL)) {
      XCTAssertEqual($0 as? ReaderFailure, .login)
    }
  }

  func testResultPageWithoutPagerStaysInMemory() throws {
    let source = "<div id='main'><div class='t'><table><tr class='tr2'><td>1</td><td>2</td><td>3</td><td>4</td><td>5</td><td>6</td><td>7</td></tr></table></div></div>"
    let page = try SouthSearch.parse(source, url: SouthSearch.formURL)
    XCTAssertTrue(page.entries.isEmpty)
    XCTAssertEqual(page.pageCount, 1)
    XCTAssertNil(page.previous)
    XCTAssertNil(page.next)
    XCTAssertNil(page.url(forPage: 1))
  }
}
