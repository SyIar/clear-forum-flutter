import Foundation
import XCTest
@testable import ForumCore

final class SouthDirectoryMetadataTests: XCTestCase {
  // Synthetic identities and content; the s8/date-cell shape is grounded in
  // the supplied tea-house directory. No account or original post data is kept.
  private func entry(title: String = "Thread", author: String = "", counts: String = "", lastReply: String = "", attributes: String = "") throws -> ForumEntry {
    let html = """
      <div id="ajaxtable"><table><tr \(attributes)>
        <td><h3><a href="read.php?tid-20.html">\(title)</a></h3><a href="read.php?tid-20-page-8.html">8</a></td>
        <td><a href="u.php?action-show-uid-101.html">Creator</a>\(author)</td>
        \(counts)
        <td><a href="u.php?action-show-uid-999.html">Last replier</a>\(lastReply)</td>
      </tr></table></div>
      """
    return try XCTUnwrap(ForumParser().parse(html, url: SouthSitePolicy.start).entries.first)
  }
  func testCreationDateComesFromCreatorCellRatherThanLastReply() throws {
    let value = try entry(author: "<div class='f10' title='Relative time'>2026-09-29 10:30</div>",
                          counts: "<td class='tal f10'><span class='s3'>7</span>/901</td>",
                          lastReply: "<div class='f10'>2026-09-30 01:00</div>")
    XCTAssertEqual(value.authorName, "Creator")
    XCTAssertEqual(value.postedAt, "2026-09-29 10:30")
    XCTAssertEqual(value.totalPostCount, 8)
  }
  func testCreatorTimeElementRetainsItsExplicitTimestamp() throws {
    let value = try entry(author: "<time datetime='2026-09-29T10:30:00+08:00'>Yesterday</time>")
    XCTAssertEqual(value.postedAt, "2026-09-29T10:30:00+08:00")
  }
  func testOnlyLastReplyDateDoesNotBecomeCreationDate() throws {
    let value = try entry(lastReply: "<time datetime='2026-09-30 01:00'>Today</time>")
    XCTAssertNil(value.postedAt)
    XCTAssertNil(value.totalPostCount)
  }
  func testExplicitTotalAndReplyCountsAreDistinguished() throws {
    XCTAssertEqual(try entry(attributes: "data-post-count='40'").totalPostCount, 40)
    XCTAssertEqual(try entry(attributes: "data-reply-count='0'").totalPostCount, 1)
    XCTAssertEqual(try entry(counts: "<td><span class='reply-count'>4</span></td>").totalPostCount, 5)
    XCTAssertEqual(try entry(counts: "<td><span class='post-count'>4</span></td>").totalPostCount, 4)
    XCTAssertEqual(try entry(counts: "<td>8 replies<br>123 views</td>").totalPostCount, 9)
  }
  func testUnknownNumbersAndMalformedCountsStayUnknown() throws {
    for count in ["<td>123</td>", "<td>123 views</td>", "<td class='f10'><span class='s3'>unknown</span>/100</td>",
                  "<td class='f10'><span class='s3'>-1</span>/100</td>", "<td class='f10'><span class='s3'>9999999999</span>/100</td>"] {
      XCTAssertNil(try entry(counts: count).totalPostCount, count)
    }
    XCTAssertNil(try entry(author: "<span class='f10'>Member since yesterday</span>").postedAt)
    XCTAssertNil(try entry(title: "8 replies and counting").totalPostCount)
  }
  func testZeroRepliesIncludeTheOriginalPost() throws {
    XCTAssertEqual(try entry(counts: "<td class='f10'><span class='s3'>0</span>/400</td>").totalPostCount, 1)
  }
  func testSuppliedDirectoryRowKeepsCreatorDateAndS8ReplyCount() throws {
    let source = """
      <div id="ajaxtable"><table><tr class="tr3 t_one">
        <td><a href="read.php?tid-20.html"><img src="images/new.gif"></a></td>
        <td><h3><a href="read.php?tid-20.html" id="a_ajax_20">Sample topic</a></h3></td>
        <td class="tal y-style"><a class="bl" href="u.php?action-show-uid-101.html">Creator</a>
          <div class="f10 gray2">2026-09-29 10:30</div></td>
        <td class="tal y-style f10"><span class="s8">7</span> / 900</td>
        <td class="tal y-style"><a class="f10" href="read.php?tid-20-page-2.html">2026-09-30 01:00</a><br>
          <span class="gray2">Last replier</span></td>
      </tr></table></div>
      """
    let value = try XCTUnwrap(ForumParser().parse(source, url: SouthSitePolicy.start).entries.first)
    XCTAssertEqual(value.title, "Sample topic")
    XCTAssertEqual(value.authorName, "Creator")
    XCTAssertEqual(value.postedAt, "2026-09-29 10:30")
    XCTAssertEqual(value.totalPostCount, 8)
  }

}
