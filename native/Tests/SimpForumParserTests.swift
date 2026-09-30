import Foundation
import XCTest
@testable import ForumCore

final class SimpForumParserTests: XCTestCase {
  func testThreadTitleComesFromHeadingWithoutPrefixAndRetainsBookmarkLocation() throws {
    let source = #"""
    <html data-template="thread_view"><title>Old tab title | SimpCity</title>
    <h1 class="p-title-value"><a class="labelLink" href="/forums/example.12/?prefix_id=3"><span class="label">Photo</span></a><span class="label-append"> </span>Actual &amp; current thread title</h1>
    <article id="post-101" class="message--post"><div class="message-body"><div class="bbWrapper">Post</div></div></article></html>
    """#
    let url = URL(string: "https://simpcity.cr/threads/old-slug.123/page-4#post-101")!
    let page = try ForumParser().parse(source, url: url)
    XCTAssertEqual(page.title, "Actual & current thread title")
    XCTAssertEqual(page.url, url)
    XCTAssertEqual(page.tags.first?.title, "Photo")
  }
}
