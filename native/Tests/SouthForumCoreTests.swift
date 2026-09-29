import Foundation
import XCTest
@testable import ForumCore

final class SouthForumCoreTests: XCTestCase {
  private func url(_ value: String) -> URL { URL(string: value, relativeTo: SouthSitePolicy.base)!.absoluteURL }
  private var directory: String {
    """
    <html><title>Tea room - South Plus</title><body>
    <div id="breadCrumb"><a href="index.php">Forums</a><a href="thread.php?fid-9.html">Tea room</a></div>
    <a href="login.php?action=quit">Sign out</a>
    <div id="ajaxtable"><table>
    <tr class="sticky"><td><img src="/headtopic.gif"></td><td><h3><a href="read.php?tid-10.html">Rules</a></h3></td><td><a href="u.php?uid=1">Moderator</a></td></tr>
    <tr><td><h3><a href="read.php?tid-20.html">A weekend walk</a></h3><a href="read.php?tid-20-page-2.html">2</a></td>
    <td><a href="u.php?uid=2">Reader</a></td><td><a href="read.php?tid-20-page-2.html#post_90">Last reply</a></td></tr>
    </table></div>
    <div class="advertisement"><a href="https://advert.example/">Sponsored</a></div>
    <div class="pages"><a href="thread.php?fid-9-page-2.html">2</a><a rel="last" href="thread.php?fid-9-page-5.html">5</a></div>
    </body></html>
    """
  }
  private func thread(floor: Int = 12, pagination: String = "") -> String {
    """
    <html><title>Weekend walk</title><body><h1 id="subject_tpc">A weekend walk</h1>
    <table><tr><td class="author">Reader</td><td>
    <div class="tiptop"><a class="floor">#\(floor)</a><span title="2026-09-29 10:30">Today</span></div>
    <div class="tpc_content" id="read_987654"><b>Hello</b><br>Readable body.
    <blockquote>A quoted line.</blockquote><div class="advertisement">Unwanted advert</div>
    <script>unwantedScript()</script><img data-src="/image.jpg" width="800" height="400">
    <p><a href="https://example.org/reference">Reference</a></p>
    <video src="https://media.example/video.mp4" poster="https://media.example/poster.jpg"></video>
    </div></td></tr></table>\(pagination)</body></html>
    """
  }

  func testLegacyAndQueryRoutesShareCacheIdentity() {
    XCTAssertEqual(SouthSitePolicy.pageCacheKey(url("read.php?tid-20-page-2.html#post_90")), SouthSitePolicy.pageCacheKey(url("read.php?page=2&tid=20&fid=9")))
    XCTAssertEqual(SouthSitePolicy.threadKey(url("read.php?tid-20-page-2.html")), "20")
    XCTAssertEqual(SouthSitePolicy.pageNumber(url("thread.php?fid-9-page-5.html")), 5)
    XCTAssertTrue(SouthSitePolicy.readable(SouthSitePolicy.start))
  }
  func testPaginationPreservesCategoryFilterAndStyle() {
    let legacy = url("thread.php?fid-9-type-3-page-2.html#row")
    XCTAssertEqual(SouthSitePolicy.pageURL(legacy, number: 4)?.query, "fid-9-type-3-page-4.html")
    XCTAssertNil(SouthSitePolicy.pageURL(legacy, number: 4)?.fragment)
    XCTAssertEqual(SouthSitePolicy.pageURL(url("thread.php?fid=9&type=3"), number: 4)?.query, "fid=9&type=3&page=4")
    XCTAssertNotEqual(SouthSitePolicy.pageCacheKey(url("thread.php?fid=9&type=3")), SouthSitePolicy.pageCacheKey(url("thread.php?fid=9&type=4")))
    XCTAssertNil(SouthSitePolicy.pageURL(legacy, number: 0))
    XCTAssertNil(SouthSitePolicy.pageURL(legacy, number: 100_000))
  }
  func testRejectsActionsAmbiguousParametersAndForeignOrigins() {
    for address in ["login.php?action=quit", "post.php?tid=20", "read.php?tid=20&action=delete", "read.php?tid=20&tid=30", "read.php?tid-20-tid-30.html", "thread.php?fid=9&page=-1", "read.php?tid-20-page-0.html", "read.php?tid=20&uid=0", "read.php?tid-20-extra.html", "https://south-plus.net.evil.example/read.php?tid=20", "https://user@south-plus.net/read.php?tid=20", "https://south-plus.net:8443/read.php?tid=20", "javascript:alert(1)"] {
      XCTAssertFalse(SouthSitePolicy.readable(url(address)), address)
    }
  }
  func testCookiesStayOnTheirHostAndPath() throws {
    let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "synthetic", .domain: ".south-plus.net", .path: "/read.php", .secure: "TRUE"]))
    XCTAssertTrue(SouthSitePolicy.matches(cookie, url: url("read.php?tid=20")))
    XCTAssertFalse(SouthSitePolicy.matches(cookie, url: url("read.php-other")))
    XCTAssertFalse(SouthSitePolicy.matches(cookie, url: URL(string: "https://media.example/read.php")!))
  }
  func testDirectoryDeduplicatesPaginationLinksAndKeepsBreadcrumbs() throws {
    let page = try ForumParser().parse(directory, url: SouthSitePolicy.start)
    XCTAssertEqual(page.entries.map(\.title), ["Rules", "A weekend walk"])
    XCTAssertTrue(page.entries[0].pinned)
    XCTAssertEqual(page.entries[1].subtitle, "Reader")
    XCTAssertEqual(page.breadcrumbs.map(\.title), ["Forums", "Tea room"])
    XCTAssertEqual(page.loggedIn, true)
    XCTAssertEqual(page.pageCount, 5)
    XCTAssertEqual(page.next?.query, "fid-9-page-2.html")
    XCTAssertNil(page.previous)
  }
  func testThreadKeepsContentButNotAdScriptsOrPostIDAsFloor() throws {
    let page = try ForumParser().parse(thread(), url: url("read.php?tid-20-page-2.html"))
    let post = try XCTUnwrap(page.posts.first)
    XCTAssertEqual(post.id, "post_987654")
    XCTAssertEqual(post.number, "#12")
    XCTAssertEqual(post.author, "Reader")
    XCTAssertEqual(post.date, "2026-09-29 10:30")
    let bodyText = post.blocks.flatMap(\.runs).map(\.text).joined()
    XCTAssertTrue(bodyText.contains("Readable body."))
    XCTAssertFalse(bodyText.contains("Unwanted"))
    XCTAssertFalse(bodyText.contains("unwantedScript"))
    XCTAssertEqual(post.blocks.first(where: { $0.kind == .image })?.aspectRatio, 2)
    XCTAssertEqual(post.blocks.first(where: { $0.kind == .media })?.poster?.host, "media.example")
    XCTAssertTrue(post.blocks.contains(where: { $0.kind == .quote }))
    XCTAssertNil(page.maximumPostNumber)
  }
  func testExplicitLastPageProvidesMaximumButMissingPagerDoesNot() throws {
    let address = url("read.php?tid-20-page-2.html")
    let pager = "<div class='pages'><a rel='last' href='read.php?tid-20-page-2.html'>2</a></div>"
    XCTAssertEqual(try ForumParser().parse(thread(pagination: pager), url: address).maximumPostNumber, 12)
    let later = "<div class='pages'><a href='read.php?tid-20-page-3.html'>3</a><a href='read.php?tid-99-page-900.html'>Foreign</a></div>"
    let result = try ForumParser().parse(thread(pagination: later), url: address)
    XCTAssertNil(result.maximumPostNumber)
    XCTAssertEqual(result.pageCount, 3)
  }
  func testUnknownLayoutNeverMasqueradesAsEmptyForum() {
    XCTAssertThrowsError(try ForumParser().parse("<html><h1>Changed layout</h1></html>", url: SouthSitePolicy.start)) { XCTAssertEqual($0 as? ReaderFailure, .unsupported) }
  }
  func testSessionFailuresAreDistinctFromParserFailure() {
    for (html, status, error) in [
      ("<form action='login.php'><input type='password'></form>", 200, ReaderFailure.login),
      ("<title>Just a moment</title>", 200, .verification),
      ("<h1>Unavailable</h1>", 403, .forbidden),
      ("<h1>Slow down</h1>", 429, .rateLimit)
    ] {
      XCTAssertThrowsError(try ForumParser().parse(html, url: SouthSitePolicy.start, status: status)) { XCTAssertEqual($0 as? ReaderFailure, error) }
    }
  }
  func testChineseEncodingDeclaredInHeaderAndMeta() throws {
    let bytes = Data([0xD6, 0xD0, 0xCE, 0xC4])
    XCTAssertEqual(try HTMLDecoder.decode(bytes, encodingName: "gb2312"), "\u{4E2D}\u{6587}")
    var html = Data("<meta charset='gbk'><p>".utf8)
    html.append(bytes); html.append(Data("</p>".utf8))
    XCTAssertTrue(try HTMLDecoder.decode(html, encodingName: nil).contains("\u{4E2D}\u{6587}"))
    XCTAssertThrowsError(try HTMLDecoder.decode(Data([0xFF, 0xFE, 0xFF]), encodingName: "utf-8"))
    XCTAssertEqual(try HTMLDecoder.decode(Data([0xEF, 0xBB, 0xBF]) + Data("Hello".utf8), encodingName: "gbk"), "Hello")
  }
  func testBoundedCacheRestoresPositionAcrossRouteAliases() throws {
    let first = try ForumParser().parse(thread(), url: url("read.php?tid-20-page-2.html"))
    let cache = PageCache(countLimit: 2, costLimit: 100)
    cache.store(first, cost: 30)
    cache.savePosition("post_987654", for: first.url)
    XCTAssertEqual(cache.value(for: url("read.php?tid=20&page=2"))?.visibleID, "post_987654")
    var second = first; second.url = url("read.php?tid=20&page=3")
    var third = first; third.url = url("read.php?tid=20&page=4")
    cache.store(second, cost: 30)
    _ = cache.value(for: first.url)
    cache.store(third, cost: 30)
    XCTAssertNil(cache.value(for: second.url))
    XCTAssertNotNil(cache.value(for: first.url))
    cache.removeAll()
    XCTAssertNil(cache.value(for: first.url))
  }
  func testBOMDecodingRejectsTruncatedDataInsteadOfFallingBack() throws {
    XCTAssertEqual(try HTMLDecoder.decode(Data([0xFF, 0xFE, 0x41, 0x00]), encodingName: "gbk"), "A")
    XCTAssertEqual(try HTMLDecoder.decode(Data([0xFE, 0xFF, 0x00, 0x41]), encodingName: "utf-8"), "A")
    for data in [Data([0xFF, 0xFE, 0x41]), Data([0xFE, 0xFF, 0x00]), Data([0xEF, 0xBB, 0xBF, 0xFF])] {
      XCTAssertThrowsError(try HTMLDecoder.decode(data, encodingName: "gbk")) { XCTAssertEqual($0 as? ReaderFailure, .encoding) }
    }
  }
  func testRecentHistoryUsesThreadIdentityAndPersistsLocally() throws {
    let name = "SouthLiteTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var library = LibraryDocument(site: .south)
    library.remember(SavedPage(url: url("read.php?tid-20.html"), title: "Walk"))
    library.remember(SavedPage(url: url("read.php?tid=20&page=2"), title: "Walk"))
    XCTAssertEqual(library.recent.count, 1)
    library.toggle(SavedPage(url: SouthSitePolicy.start, title: "Tea room"))
    try library.save(to: defaults)
    let restored = try LibraryDocument.load(from: defaults, site: .south)
    XCTAssertEqual(restored.recent.first?.url.query, "tid=20&page=2")
    XCTAssertEqual(restored.bookmarks.count, 1)
  }
  func testUpdateChecksNeverAdvanceReadBaseline() {
    var state = ThreadReadState()
    state.opened(maximum: 100)
    state.checked(maximum: 108)
    XCTAssertTrue(state.updated)
    XCTAssertEqual(state.seenMaximum, 100)
    state.opened(maximum: 108)
    XCTAssertFalse(state.updated)
  }
}
