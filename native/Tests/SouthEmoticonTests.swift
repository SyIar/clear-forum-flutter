import Foundation
import SwiftSoup
import XCTest
@testable import ForumCore

final class SouthEmoticonTests: XCTestCase {
  private let page = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private func parse(_ html: String) throws -> [BodyBlock] {
    let body = try XCTUnwrap(SwiftSoup.parseBodyFragment(html).body())
    return try SouthBodyParser().parseBody(body, page: page)
  }

  func testSmileImagesStayInlineWithTextAndFormatting() throws {
    let blocks = try parse("""
      <p>Before <b><img src="/images/post/smile/smallface/face077.gif" width="800" height="800" alt=":smile:">after</b> end</p>
      """)
    XCTAssertEqual(blocks.count, 1)
    XCTAssertEqual(blocks[0].kind, .paragraph)
    XCTAssertEqual(blocks[0].runs.map(\.text).joined(), "Before :smile:after end")
    let image = try XCTUnwrap(blocks[0].runs.first { $0.emoticon != nil })
    XCTAssertEqual(image.emoticon?.absoluteString, "https://south-plus.net/images/post/smile/smallface/face077.gif")
    XCTAssertTrue(image.bold)
  }
  func testEmojiOnlyParagraphAndLazySourcesAreNotDropped() throws {
    let blocks = try parse("""
      <img class="smilie" src="/placeholder.gif" data-src="http://south-plus.net/images/post/smile/smallface/face077.gif">
      <img src="//south-plus.net/images/post/smile/other/face001.png?version=2">
      """)
    XCTAssertEqual(blocks.count, 1)
    let sources = blocks[0].runs.compactMap(\.emoticon)
    XCTAssertEqual(sources.count, 2)
    XCTAssertTrue(sources.allSatisfy { $0.scheme == "https" })
    XCTAssertTrue(blocks[0].runs.contains { $0.text == "Emoticon" })
  }
  func testOrdinaryPhotosAndLookalikeHostsStillUseImageLayout() throws {
    let blocks = try parse("""
      <img src="/uploads/photo.jpg"><img src="https://south-plus.net.evil.example/images/post/smile/face077.gif">
      <img src="/images/post/smile-extra/face077.gif"><img src="/images/post/smile/../../../photo.jpg">
      """)
    XCTAssertEqual(blocks.count, 4)
    XCTAssertTrue(blocks.allSatisfy { $0.kind == .image })
    XCTAssertTrue(blocks.flatMap(\.runs).compactMap(\.emoticon).isEmpty)
  }
  func testQuotedEmoticonsDoNotSplitTheQuoteOrSurroundingLinks() throws {
    let blocks = try parse("""
      <blockquote><a href="https://example.org/">Source</a> <img src="/images/post/smile/smallface/face077.gif"> text</blockquote>
      <img src="/uploads/full-photo.png">
      """)
    XCTAssertEqual(blocks.count, 2)
    XCTAssertEqual(blocks[0].kind, .quote)
    let child = try XCTUnwrap(blocks[0].children.first)
    XCTAssertEqual(blocks[0].children.count, 1)
    XCTAssertEqual(child.runs.first?.url?.host, "example.org")
    XCTAssertEqual(child.runs.compactMap(\.emoticon).count, 1)
    XCTAssertEqual(blocks[1].kind, .image)
  }
}
