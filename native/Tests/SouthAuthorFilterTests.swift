import Foundation
import XCTest
@testable import ForumCore

final class SouthAuthorFilterTests: XCTestCase {
  private func url(_ query: String) -> URL { URL(string: "https://south-plus.net/read.php?" + query)! }
  private func page(_ query: String, pager: String = "") throws -> ForumPage {
    let html = """
      <h1 id="subject_tpc">Sample thread</h1>
      <article class="post" data-floor="42"><span class="author">Reader</span>
        <div data-post-body>Sample reply</div>
      </article>\(pager)
      """
    return try ForumParser().parse(html, url: url(query))
  }

  func testAuthorRoutesPreserveUIDThroughPaginationAndAliases() throws {
    let legacy = url("tid-20-uid-101-page-2.html#post_42")
    let query = url("page=2&uid=101&tid=20&fid=9")
    XCTAssertTrue(ForumSite.south.accepts(legacy))
    XCTAssertEqual(SouthSitePolicy.authorID(legacy), "101")
    XCTAssertEqual(SitePolicy.pageCacheKey(legacy), SitePolicy.pageCacheKey(query))
    XCTAssertEqual(SitePolicy.pageURL(legacy, number: 5)?.query, "tid-20-uid-101-page-5.html")
    XCTAssertEqual(SitePolicy.pageURL(query, number: 5)?.query, "tid-20-fid-9-uid-101-page-5.html")
    XCTAssertEqual(SitePolicy.pageURL(legacy, number: 1)?.query, "tid-20-uid-101.html")
    XCTAssertNil(SitePolicy.pageURL(legacy, number: 1)?.fragment)
    XCTAssertEqual(SouthSitePolicy.pageRoot(legacy), SouthSitePolicy.pageRoot(query))
    XCTAssertNotEqual(SouthSitePolicy.pageRoot(legacy), SouthSitePolicy.pageRoot(url("tid=20")))
  }

  func testInvalidAuthorFiltersRemainUnsupported() {
    for query in ["tid=20&uid=0", "tid=20&uid=-1", "tid=20&uid=member", "tid=20&uid=01",
                  "tid=20&uid=101&uid=102", "tid-20-uid-101-uid-102.html", "uid=101",
                  "tid=20&uid=101&action=delete", "tid=20&uid=9999999999999999999"] {
      XCTAssertFalse(SouthSitePolicy.readable(url(query)), query)
      XCTAssertNil(SouthSitePolicy.authorID(url(query)), query)
    }
    XCTAssertFalse(SouthSitePolicy.readable(URL(string: "https://south-plus.net/thread.php?fid=9&uid=101")!))
  }

  func testFilteredPagerCannotNavigateToWholeThreadOrAnotherAuthor() throws {
    let pager = """
      <div class="pages">
        <a href="read.php?tid-20-uid-101.html">1</a>
        <a href="read.php?tid-20-uid-101-page-3.html">3</a>
        <a rel="last" href="read.php?tid-20-uid-101-page-4.html">4</a>
        <a href="read.php?tid-20-page-99.html">All authors</a>
        <a href="read.php?tid-20-uid-102-page-90.html">Other author</a>
      </div>
      """
    let result = try page("tid-20-uid-101-page-2.html", pager: pager)
    XCTAssertEqual(result.pageCount, 4)
    XCTAssertEqual(result.previous?.query, "tid-20-uid-101.html")
    XCTAssertEqual(result.next?.query, "tid-20-uid-101-page-3.html")
    XCTAssertEqual(result.url(forPage: 4)?.query, "tid-20-uid-101-page-4.html")
    XCTAssertNil(result.url(forPage: 5))
  }

  func testAuthorLastPageCannotOverwriteThreadMaximum() throws {
    let filteredPager = "<div class='pages'><a rel='last' href='read.php?tid-20-uid-101.html'>1</a><input name='page' max='1'></div>"
    XCTAssertNil(try page("tid-20-uid-101.html", pager: filteredPager).maximumPostNumber)
    let fullPager = "<div class='pages'><a rel='last' href='read.php?tid-20.html'>1</a></div>"
    XCTAssertEqual(try page("tid-20.html", pager: fullPager).maximumPostNumber, 42)
    let wrongPager = "<div class='pages'><a rel='last' href='read.php?tid-20-uid-101.html'>1</a></div>"
    XCTAssertNil(try page("tid-20.html", pager: wrongPager).maximumPostNumber)
  }

  func testCachedPositionsAreSeparateButThreadInvalidationCoversEveryAuthor() throws {
    let full = try page("tid-20.html")
    let first = try page("tid-20-uid-101.html")
    let second = try page("tid-20-uid-102.html")
    let otherThread = try page("tid-30.html")
    let cache = PageCache()
    for value in [full, first, second, otherThread] { cache.store(value) }
    cache.savePosition("full-position", for: full.url)
    cache.savePosition("author-position", for: first.url)
    XCTAssertEqual(cache.count, 4)
    XCTAssertEqual(cache.value(for: url("tid=20&uid=101"))?.visibleID, "author-position")
    XCTAssertEqual(cache.value(for: full.url)?.visibleID, "full-position")
    XCTAssertNil(cache.value(for: second.url)?.visibleID)
    cache.removeThread(first.url)
    XCTAssertEqual(cache.count, 1)
    for value in [full, first, second] { XCTAssertNil(cache.value(for: value.url)) }
    XCTAssertNotNil(cache.value(for: otherThread.url))
  }

  func testLibraryTracksWholeThreadWhileRetainingFilteredReadingLocation() {
    let filtered = url("tid-20-uid-101-page-3.html")
    XCTAssertEqual(SitePolicy.threadRoot(filtered), url("tid=20"))
    XCTAssertEqual(SitePolicy.threadKey(filtered), SitePolicy.threadKey(url("tid=20")))
    var library = LibraryDocument(site: .south)
    library.remember(SavedPage(url: url("tid=20"), title: "Sample"))
    library.remember(SavedPage(url: filtered, title: "Sample"))
    XCTAssertEqual(library.recent.count, 1)
    XCTAssertEqual(library.recent.first?.url, filtered)
    XCTAssertEqual(library.trackedThreads, [url("tid=20")])
  }
}
