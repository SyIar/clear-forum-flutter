import Foundation
import XCTest
@testable import ForumCore

final class SouthAuthorTopicsTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/u.php?action-topic-uid-101.html")!
  private let html = """
    <div id="menu_profile"><a href="u.php?action-topic-uid-999.html">Signed-in account</a></div>
    <div id="u-top"><h1 class="u-h1">Sample author</h1></div>
    <div id="u-contentmain"><table class="u-table">
      <tr><td><br></td><td width="17%"><br></td></tr>
      <tr><th><a href="read.php?tid-20.html">First topic</a><br>
        <a class="gray" href="thread.php?fid-9.html">Tea room</a><span class="gray f9">2026-09-29</span>
        </th><td>8 replies<br>12 views</td></tr>
      <tr><th><a href="read.php?tid-21.html">Second topic</a><br>
        <a class="gray" href="thread.php?fid-9.html">Tea room</a><span class="gray f9">2026-09-28</span>
        </th><td>2 replies<br>6 views</td></tr>
    </table><div class="pages">
      <a href="u.php?action-topic-uid-101-page-1.html">First</a>
      <a href="u.php?action-topic-uid-101-page-2.html">2</a>
      <a href="u.php?action-topic-uid-101-page-11.html">11</a>
      <a href="u.php?action-topic-uid-999-page-99.html">Other user</a>
    </div></div>
    <div id="u-contentside"><table><tr><td><a href="read.php?tid-999.html">Unrelated</a></td></tr></table></div>
    """
  func testOnlyReadOnlyAuthorTopicsRouteIsAccepted() throws {
    let alias = URL(string: "https://south-plus.net/u.php?uid=101&action=topic&page=1")!
    XCTAssertTrue(ForumSite.south.accepts(url))
    XCTAssertEqual(SitePolicy.pageCacheKey(url), SitePolicy.pageCacheKey(alias))
    XCTAssertEqual(SouthSitePolicy.topicAuthorID(url), "101")
    XCTAssertNil(SouthSitePolicy.authorID(url))
    XCTAssertNil(SitePolicy.threadKey(url))
    XCTAssertEqual(SouthSitePolicy.authorTopics("101"), url)
    XCTAssertNil(SouthSitePolicy.authorTopics("0"))
    XCTAssertNil(SouthSitePolicy.authorTopics("101&action=delete"))
    for query in ["action-show-uid-101.html", "action-edit-uid-101.html", "action-friend-uid-101.html",
                  "action-topic.html", "action-topic-uid-0.html", "action-topic-uid-101-skinco-wind.html",
                  "action=topic&uid=101&uid=102", "action=topic&uid=101&action=edit"] {
      XCTAssertFalse(SouthSitePolicy.readable(URL(string: "https://south-plus.net/u.php?" + query)!), query)
    }
    XCTAssertFalse(SouthSitePolicy.readable(URL(string: "https://example.org/u.php?action-topic-uid-101.html")!))
  }
  func testProfileTopicsUseURLAuthorAndIgnoreSidebarThreads() throws {
    let page = try ForumParser().parse(html, url: url)
    XCTAssertEqual(page.kind, .threads)
    XCTAssertEqual(page.title, "Sample author - Threads")
    XCTAssertEqual(page.entries.map(\.title), ["First topic", "Second topic"])
    XCTAssertEqual(page.entries.compactMap(\.authorID), ["101", "101"])
    XCTAssertEqual(page.entries[0].subtitle, "Tea room \u{00B7} 2026-09-29")
    XCTAssertEqual(page.pageCount, 11)
    XCTAssertEqual(page.next?.query, "action-topic-uid-101-page-2.html")
    XCTAssertEqual(page.url(forPage: 11)?.query, "action-topic-uid-101-page-11.html")
    XCTAssertNil(page.maximumPostNumber)
    let second = try ForumParser().parse(html, url: SouthSitePolicy.pageURL(url, number: 2)!)
    XCTAssertEqual(second.previous?.query, "action-topic-uid-101-page-1.html")
  }
  func testEmptyHistoryAndUnknownMarkupRemainDistinct() throws {
    let empty = "<div id='u-contentmain'><table class='u-table'><tr><td>No topics</td></tr></table></div>"
    XCTAssertTrue(try ForumParser().parse(empty, url: url).entries.isEmpty)
    XCTAssertThrowsError(try ForumParser().parse("<h1>Unexpected response</h1>", url: url))
  }
  func testDirectoryCreatorIDIsNotTheLastReplyAuthor() throws {
    let source = """
      <div id="ajaxtable"><table><tr>
        <td><h3><a href="read.php?tid-20.html">Topic</a></h3></td>
        <td><a href="u.php?action-show-uid-101.html">Creator</a></td>
        <td><a href="u.php?action-show-uid-999.html">Last reply author</a></td>
      </tr></table></div>
      """
    let entry = try XCTUnwrap(ForumParser().parse(source, url: SouthSitePolicy.start).entries.first)
    XCTAssertEqual(entry.authorID, "101")
    XCTAssertEqual(entry.subtitle, "Creator")
  }
  func testOriginalAvatarUsesExplicitSourceWithoutGuessingFileNames() throws {
    let source = """
      <table class="js-post"><tr><th class="r_two">
        <a href="u.php?action-show-uid-101.html"><img src="images/avatar-small.png" data-original="images/avatar-full.png"></a>
        <a href="u.php?action-show-uid-101.html"><b>Creator</b></a>
      </th><td><div class="tpc_content"><div id="read_tpc">Hello</div></div></td></tr></table>
      """
    let post = try XCTUnwrap(ForumParser().parse(source, url: URL(string: "https://south-plus.net/read.php?tid-20.html")!).posts.first)
    XCTAssertEqual(post.avatar?.path, "/images/avatar-small.png")
    XCTAssertEqual(post.avatarOriginal?.path, "/images/avatar-full.png")
  }
}
