import Foundation
import XCTest
@testable import ForumCore

final class SouthThreadURLTests: XCTestCase {
  private func url(_ path: String) -> URL {
    URL(string: path, relativeTo: SouthSitePolicy.base)!.absoluteURL
  }

  func testFullThreadsUseQuerySyntaxWhileAuthorFiltersKeepLegacySyntax() {
    let cases = [
      ("read.php?tid-2973920.html", "read.php?tid=2973920"),
      ("read.php?tid-20-fid-9-page-3.html#post_42", "read.php?tid=20&fid=9&page=3#post_42"),
      ("read.php?tid-2973760-uid-1191634.html", "read.php?tid-2973760-uid-1191634.html"),
      ("read.php?tid-20-fid-9-uid-101-page-3.html#post_42", "read.php?tid-20-fid-9-uid-101-page-3.html#post_42"),
      ("read.php?page=3&uid=101&tid=20#post_42", "read.php?tid-20-uid-101-page-3.html#post_42"),
      ("read.php?tid-20-fpage-0-toread--page-2.html", "read.php?tid=20&page=2"),
      ("read.php?tid-20-fpage-2.html", "read.php?tid=20"),
      ("read.php?tid-20-uid-101-fpage-2.html", "read.php?tid-20-uid-101.html")
    ]
    for (source, expected) in cases {
      let target = SouthSitePolicy.canonicalThreadURL(url(source))
      XCTAssertEqual(target, url(expected))
      XCTAssertEqual(SouthSitePolicy.canonicalThreadURL(target), target)
      XCTAssertEqual(SitePolicy.pageCacheKey(url(source)), SitePolicy.pageCacheKey(target))
    }
  }

  func testActionsForeignSitesAndOtherSouthRoutesAreNotRewritten() {
    for source in ["read.php?tid=20&action=buy", "read.php?tid=20&uid=101&uid=102",
                   "read.php?tid-20-fpage-100000.html", "thread.php?fid-9-page-2.html",
                   "u.php?action-topic-uid-101.html", "login.php", "job.php?action=buytopic&tid=20",
                   "https://example.org/read.php?tid-20.html", "https://simpcity.cr/threads/sample.20/page-2#post-42"] {
      XCTAssertEqual(SouthSitePolicy.canonicalThreadURL(url(source)), url(source), source)
    }
  }

  func testResolvedAndRequestedLinksKeepRequiredFormatCookiesAndIdentity() throws {
    let legacy = url("read.php?tid-20-uid-101-page-3.html#post_42")
    let expected = legacy
    XCTAssertEqual(SouthSitePolicy.resolve("read.php?tid-20-uid-101-page-3.html#post_42", from: SouthSitePolicy.start), expected)
    XCTAssertEqual(SouthSitePolicy.resolve("http://south-plus.net/read.php?tid-20.html", from: SouthSitePolicy.start), url("read.php?tid=20"))
    let cookie = try XCTUnwrap(HTTPCookie(properties: [
      .name: "fixture_session", .value: "synthetic", .domain: ".south-plus.net", .path: "/", .secure: "TRUE"
    ]))
    let request = try ForumRequest.page(site: .south, url: legacy, userAgent: "Desktop-fixture", cookies: [cookie])
    XCTAssertEqual(request.url, url("read.php?tid-20-uid-101-page-3.html"))
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Desktop-fixture")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "fixture_session=synthetic")
    XCTAssertEqual(request.httpMethod, "GET")
    let full = try ForumRequest.page(site: .south, url: url("read.php?tid-20-page-3.html#post_42"), userAgent: "Desktop-fixture", cookies: [cookie])
    XCTAssertEqual(full.url, url("read.php?tid=20&page=3"))
    XCTAssertEqual(full.value(forHTTPHeaderField: "Cookie"), "fixture_session=synthetic")
    XCTAssertEqual(ForumRequest.redirect("read.php?tid-20-page-4.html", from: expected), url("read.php?tid=20&page=4#post_42"))
    XCTAssertEqual(ForumRequest.redirect("read.php?tid=20&uid=101&page=4", from: expected), url("read.php?tid-20-uid-101-page-4.html#post_42"))
  }

  func testParserNormalizesThreadDestinationsAndItsOwnPageURL() throws {
    let directory = "<div id='ajaxtable'><table><tr><td><h3><a href='read.php?tid-20.html'>Sample</a></h3></td></tr></table></div>"
    let listing = try ForumParser().parse(directory, url: SouthSitePolicy.start)
    XCTAssertEqual(listing.entries.first?.url, url("read.php?tid=20"))
    let thread = try ForumParser().parse("<div class='tpc_content' id='read_tpc'>Sample</div>", url: url("read.php?tid-20-uid-101-page-3.html#post_42"))
    XCTAssertEqual(thread.url, url("read.php?tid-20-uid-101-page-3.html#post_42"))
    let full = try ForumParser().parse("<div class='tpc_content' id='read_tpc'>Sample</div>", url: url("read.php?tid-20-page-3.html#post_42"))
    XCTAssertEqual(full.url, url("read.php?tid=20&page=3#post_42"))
  }

  func testExistingBookmarkAliasesRemainSelectedAndCanBeRemoved() {
    var library = LibraryDocument(site: .south)
    let old = SavedPage(url: url("read.php?tid-20-uid-101-page-3.html#post_42"), title: "Saved location")
    library.bookmarks = [old]
    let current = url("read.php?tid=20&uid=101&page=3#post_42")
    XCTAssertTrue(library.containsBookmark(current))
    XCTAssertEqual(library.bookmarks, [old])
    for other in ["read.php?tid=20&uid=102&page=3#post_42", "read.php?tid=20&uid=101&page=2#post_42",
                  "read.php?tid=20&uid=101&page=3#post_43"] {
      XCTAssertFalse(library.containsBookmark(url(other)))
    }
    library.toggle(SavedPage(url: current, title: "Saved location"))
    XCTAssertTrue(library.bookmarks.isEmpty)
    library.bookmarks = [SavedPage(url: url("read.php?tid-20-page-3.html#post_42"), title: "Full thread")]
    XCTAssertTrue(library.containsBookmark(url("read.php?tid=20&page=3#post_42")))
    library.toggle(SavedPage(url: url("read.php?tid=20&page=3#post_42"), title: "Full thread"))
    XCTAssertTrue(library.bookmarks.isEmpty)
  }
}
