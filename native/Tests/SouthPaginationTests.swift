import Foundation
import XCTest
@testable import ForumCore

final class SouthPaginationTests: XCTestCase {
  func testSecondDirectoryPageRetainsTitlesWithObservedFpageHints() throws {
    func parsed(_ number: Int) throws -> ForumPage {
      let url = URL(string: "https://south-plus.net/thread.php?fid-9-page-\(number).html")!
      let html = """
        <div id="ajaxtable"><table><tr><td><h3><a href="read.php?tid-\(100 + number)-fpage-\(number).html">Sample title</a></h3></td></tr></table></div>
        <div class="pages"><span class="pagesone">Pages: \(number)/8</span></div>
        """
      return try ForumParser().parse(html, url: url)
    }
    let first = try parsed(1)
    let second = try parsed(2)
    XCTAssertEqual(second.entries.count, 1)
    XCTAssertEqual(second.entries[0].url.query, "tid=102")
    XCTAssertEqual(second.pageNumber, 2)
    var window = ReaderPageWindow()
    window.reset(first)
    XCTAssertEqual(window.target(.next), second.url)
    XCTAssertTrue(window.insert(second, at: .next, keeping: first.url))
    XCTAssertEqual(window.combined(active: second).entries.count, 2)
    XCTAssertEqual(window.target(.next)?.query, "fid-9-page-3.html")
  }
  func testDirectoryOriginHintDoesNotChangeThreadIdentityOrAuthorFilter() throws {
    for number in [0, 1, 2, 42, 99_999] {
      let url = URL(string: "https://south-plus.net/read.php?tid-20-uid-101-fpage-\(number)-page-3.html")!
      XCTAssertEqual(SouthSitePolicy.canonicalThreadURL(url).query, "tid-20-uid-101-page-3.html")
      XCTAssertEqual(SouthSitePolicy.pageCacheKey(url), SouthSitePolicy.pageCacheKey(URL(string: "https://south-plus.net/read.php?tid-20-uid-101-page-3.html")!))
    }
    for hint in ["-1", "100000", "1x", "01", ""] {
      XCTAssertFalse(SouthSitePolicy.readable(URL(string: "https://south-plus.net/read.php?tid=20&fpage=" + hint)!))
    }
  }
  // User-supplied PHPWind pager structures, with synthetic thread IDs and
  // content. Account data and event handlers are not retained.
  private func page(_ pager: String, number: Int = 1) throws -> ForumPage {
    let url = URL(string: "https://south-plus.net/thread.php?fid-9-type-3-page-\(number).html")!
    let html = "<div id='ajaxtable'><table><tr><td><h3><a href='read.php?tid-20.html'>Topic</a></h3></td></tr></table></div>" + pager
    return try ForumParser().parse(html, url: url)
  }
  func testPagesoneCountEnablesNextAndExactPageChoiceWithoutNumberedAnchors() throws {
    let value = try page("<div class='pages'><span class='pagesone'>Pages: 1/42</span></div>")
    XCTAssertEqual(value.pageCount, 42)
    XCTAssertEqual(value.next?.query, "fid-9-type-3-page-2.html")
    XCTAssertEqual(value.lastPage?.query, "fid-9-type-3-page-42.html")
    XCTAssertEqual(value.url(forPage: 42)?.query, "fid-9-type-3-page-42.html")
    XCTAssertNil(value.previous)
  }
  func testPagerRootAndJumpInputCanDeclareBoundedTotals() throws {
    for pager in ["<div class='pages' data-total-pages='12'></div>",
                  "<div class='pagination' data-total-pages='12'></div>",
                  "<div class='page-nav'><input name='jump_page' max='12'></div>"] {
      let value = try page(pager, number: 2)
      XCTAssertEqual(value.pageCount, 12)
      XCTAssertEqual(value.previous?.query, "fid-9-type-3.html")
      XCTAssertEqual(value.next?.query, "fid-9-type-3-page-3.html")
    }
  }
  func testDeclaredLastPageHasPreviousButNoNext() throws {
    let value = try page("<div class='pagesone'>Pages: 42/42</div>", number: 42)
    XCTAssertEqual(value.pageCount, 42)
    XCTAssertNil(value.next)
    XCTAssertEqual(value.previous?.query, "fid-9-type-3-page-41.html")
  }
  func testStaleMalformedAndOutOfRangeLabelsCannotInventPages() throws {
    for label in ["Pages: 2/42", "Pages: 1/0", "Pages: 1/100000", "Pages: 1/-8", "Posts: 1/42", "42"] {
      let value = try page("<span class='pagesone'>\(label)</span>")
      XCTAssertEqual(value.pageCount, 1, label)
      XCTAssertNil(value.next, label)
    }
  }
  func testQuotedPagerAndForeignOrActionLinksCannotChangePageRange() throws {
    let value = try page("""
      <blockquote><div class="pages" data-total-pages="900"><span class="pagesone">Pages: 1/900</span>
        <a href="thread.php?fid-9-type-3-page-900.html">900</a></div></blockquote>
      <div class="pages"><a href="thread.php?fid-10-type-3-page-90.html">Other forum</a>
        <a href="thread.php?fid-9-type-4-page-80.html">Other filter</a>
        <a rel="next" href="https://example.org/thread.php?fid-9-type-3-page-2.html">Foreign</a>
        <a href="job.php?action=buytopic&amp;tid=20&amp;pid=tpc&amp;verify=synthetic">Action</a></div>
      """)
    XCTAssertEqual(value.pageCount, 1)
    XCTAssertNil(value.next)
  }
  func testDeclaredFinalThreadPageCanEstablishMaximumFloorButQuotedLabelsCannot() throws {
    let url = URL(string: "https://south-plus.net/read.php?tid-20-page-2.html")!
    let body = "<table><tr><td><div class='tiptop'><a class='floor'>#12</a></div><div class='tpc_content' id='read_987'>Body</div></td></tr></table>"
    let final = try ForumParser().parse(body + "<div class='pagesone'>Pages: 2/2</div>", url: url)
    XCTAssertEqual(final.maximumPostNumber, 12)
    let quote = try ForumParser().parse(body + "<blockquote><div class='pagesone'>Pages: 2/2</div></blockquote>", url: url)
    XCTAssertNil(quote.maximumPostNumber)
  }

  func testSuppliedTeaHousePagerKeepsItsTenThousandPageRange() throws {
    let url = SouthSitePolicy.start
    let source = """
      <div id="ajaxtable"><table><tr><td><h3><a href="read.php?tid-20.html">Topic</a></h3></td></tr></table></div>
      <div class="pages"><ul><li><a href="thread.php?fid-9-page-1.html">First</a></li>
        <li><b>1</b></li><li><a href="thread.php?fid-9-page-2.html">2</a></li>
        <li><a href="thread.php?fid-9-page-5.html">5</a></li>
        <li><a href="thread.php?fid-9-page-10342.html">Last</a></li>
        <li class="pagesone">Pages: 1/10342&nbsp; &nbsp; &nbsp;Go <input type="text" size="3"></li>
      </ul></div>
      """
    let value = try ForumParser().parse(source, url: url)
    XCTAssertEqual(value.pageCount, 10_342)
    XCTAssertEqual(value.next?.query, "fid-9-page-2.html")
    XCTAssertEqual(value.url(forPage: 10_342)?.query, "fid-9-page-10342.html")
    XCTAssertNil(value.url(forPage: 10_343))
  }
  func testSuppliedPagesoneGoSuffixWorksWithoutNumberedLinks() throws {
    let value = try page("<div class='pages'><li class='pagesone'>Pages: 1/10342&nbsp; &nbsp; &nbsp;Go <input type='text' size='3'></li></div>")
    XCTAssertEqual(value.pageCount, 10_342)
    XCTAssertEqual(value.lastPage?.query, "fid-9-type-3-page-10342.html")
  }
  func testObservedNeutralThreadNavigationHintsShareCanonicalReadIdentity() throws {
    let canonical = URL(string: "https://south-plus.net/read.php?tid-20-page-2.html")!
    let observed = URL(string: "https://south-plus.net/read.php?tid-20-fpage-0-toread--page-2.html")!
    let queryAlias = URL(string: "https://south-plus.net/read.php?tid=20&fpage=0&toread=&page=2")!
    XCTAssertTrue(SouthSitePolicy.readable(observed))
    XCTAssertEqual(SouthSitePolicy.pageCacheKey(observed), SouthSitePolicy.pageCacheKey(canonical))
    XCTAssertEqual(SouthSitePolicy.pageCacheKey(queryAlias), SouthSitePolicy.pageCacheKey(canonical))
    XCTAssertEqual(SouthSitePolicy.pageURL(observed, number: 3)?.query, "tid=20&page=3")
    for query in ["tid-20-fpage-100000-toread--page-2.html", "tid-20-fpage-0-toread-1-page-2.html",
                  "tid=20&fpage=0&fpage=0", "tid=20&toread=&toread=", "tid=20&fpage=0&action=delete"] {
      XCTAssertFalse(SouthSitePolicy.readable(URL(string: "https://south-plus.net/read.php?" + query)!))
    }
    XCTAssertFalse(SouthSitePolicy.readable(URL(string: "https://south-plus.net/thread.php?fid=9&fpage=0&toread=")!))
  }
  func testSuppliedThreadPageLinksWithNeutralHintsRemainNavigable() throws {
    let url = URL(string: "https://south-plus.net/read.php?tid-20.html")!
    let body = "<div class='tpc_content' id='read_tpc'>Sample</div>"
    let pager = """
      <div class="pages"><ul>
        <li><a href="read.php?tid-20-fpage-0-toread--page-2.html">2</a></li>
        <li><a href="read.php?tid-20-fpage-0-toread--page-4.html">Last</a></li>
        <li class="pagesone">Pages: 1/4&nbsp; Go <input type="text" size="3"></li>
      </ul></div>
      """
    let value = try ForumParser().parse(body + pager, url: url)
    XCTAssertEqual(value.pageCount, 4)
    XCTAssertEqual(value.next.map(SouthSitePolicy.pageNumber), 2)
    XCTAssertEqual(value.url(forPage: 4)?.query, "tid=20&page=4")
  }

}
