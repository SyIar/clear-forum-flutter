import Foundation
import SwiftSoup
import XCTest
@testable import ForumCore

final class SouthTextLinksTests: XCTestCase {
  private let page = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private func parse(_ html: String) throws -> [BodyBlock] {
    let root = try XCTUnwrap(SwiftSoup.parseBodyFragment(html).body())
    return try SouthBodyParser().parseBody(root, page: page)
  }
  func testBareHTTPSAndHTTPLinksBecomeClickableWithoutLosingText() {
    let text = "Download https://example.org/file?code=a%2Fb&key=42#part then http://legacy.example:8080/archive."
    let runs = SouthTextLinks.detect(in: [TextRun(text: text)])
    XCTAssertEqual(runs.map(\.text).joined(), text)
    XCTAssertEqual(runs.compactMap(\.url).map(\.absoluteString), ["https://example.org/file?code=a%2Fb&key=42#part", "http://legacy.example:8080/archive"])
    XCTAssertNil(runs.last?.url)
    XCTAssertEqual(runs.last?.text, ".")
  }
  func testUnicodeSurroundingsAndSentencePunctuationStayOutsideTheLink() {
    let text = "\u{1F517}\u{5730}\u{5740}\u{FF1A}https://example.org/file\u{FF0C}\u{63D0}\u{53D6}\u{7801}: abcd\u{3002}"
    let runs = SouthTextLinks.detect(in: [TextRun(text: text)])
    XCTAssertEqual(runs.map(\.text).joined(), text)
    XCTAssertEqual(runs.compactMap(\.url).map(\.absoluteString), ["https://example.org/file"])
    XCTAssertNil(runs.first?.url)
    XCTAssertNil(runs.last?.url)
  }
  func testBalancedParenthesesAndEncodedPunctuationArePreserved() {
    let text = "(https://example.org/wiki/Thing_(version)). [https://example.org/a%29b?q=x%2Cy]"
    let runs = SouthTextLinks.detect(in: [TextRun(text: text)])
    XCTAssertEqual(runs.compactMap(\.url).map(\.absoluteString), ["https://example.org/wiki/Thing_(version)", "https://example.org/a%29b?q=x%2Cy"])
    XCTAssertEqual(runs.map(\.text).joined(), text)
  }
  func testURLSplitAcrossFormattingKeepsFormattingAndFullDestination() throws {
    let blocks = try parse("Before https://<b>example.org</b>/file<i>?x=1&amp;y=2</i> after")
    let runs = blocks[0].runs
    let linked = runs.filter { $0.url != nil }
    XCTAssertEqual(Set(linked.compactMap(\.url).map(\.absoluteString)), ["https://example.org/file?x=1&y=2"])
    XCTAssertTrue(linked.contains { $0.text == "example.org" && $0.bold })
    XCTAssertTrue(linked.contains { $0.text == "?x=1&y=2" && $0.italic })
    XCTAssertEqual(runs.map(\.text).joined(), "Before https://example.org/file?x=1&y=2 after")
  }
  func testExistingAnchorDestinationWinsOverItsDisplayedURL() throws {
    let blocks = try parse("<a href='https://target.example/download'><b>https://label.example/</b></a> http://legacy.example/file")
    let runs = blocks[0].runs
    XCTAssertEqual(runs.first?.url?.host, "target.example")
    XCTAssertEqual(runs.first?.text, "https://label.example/")
    XCTAssertEqual(runs.last?.url?.scheme, "http")
    XCTAssertEqual(runs.last?.url?.host, "legacy.example")
  }
  func testExistingHTTPAnchorAndSouthHTTPRouteCanBeOpened() throws {
    let blocks = try parse("<a href='http://legacy.example/file'>Download</a> HTTP://south-plus.net/read.php?tid-21.html")
    XCTAssertEqual(blocks[0].runs.first?.url?.absoluteString, "http://legacy.example/file")
    let local = try XCTUnwrap(blocks[0].runs.last?.url)
    XCTAssertEqual(local.scheme, "https")
    XCTAssertEqual(SouthSitePolicy.threadKey(local), "21")
  }
  func testQuotesSpoilersAndEmoticonParagraphsAlsoLinkify() throws {
    let blocks = try parse("""
      <blockquote>https://quote.example/</blockquote>
      <span class='bbCodeInlineSpoiler'>https://hidden.example/</span>
      <p>https://example.org/ <img src='/images/post/smile/smallface/face077.gif'> http://legacy.example/</p>
      """)
    let quote = try XCTUnwrap(blocks.first { $0.kind == .quote })
    let spoiler = try XCTUnwrap(blocks.first { $0.kind == .spoiler })
    XCTAssertEqual(quote.children.first?.runs.first?.url?.host, "quote.example")
    XCTAssertEqual(spoiler.children.first?.runs.first?.url?.host, "hidden.example")
    let paragraph = try XCTUnwrap(blocks.first { $0.runs.contains { $0.emoticon != nil } })
    XCTAssertEqual(paragraph.runs.compactMap(\.url).count, 2)
    XCTAssertEqual(paragraph.runs.compactMap(\.emoticon).count, 1)
  }
  func testCodeRemainsLiteral() throws {
    let blocks = try parse("<p><code>https://code.example/</code> text</p><pre>http://sample.example/</pre>")
    XCTAssertTrue(blocks.flatMap(\.runs).compactMap(\.url).isEmpty)
    XCTAssertEqual(blocks.last?.kind, .code)
    XCTAssertEqual(blocks.last?.label, "http://sample.example/")
  }
  func testInvalidOrEmptyAnchorCanRecoverAVisibleHTTPAddress() throws {
    let blocks = try parse("<a href='javascript:alert(1)'>https://example.org/file</a> <a>http://legacy.example/</a>")
    XCTAssertEqual(blocks.flatMap(\.runs).compactMap(\.url).map(\.absoluteString), ["https://example.org/file", "http://legacy.example/"])
  }
  func testUnsupportedSchemesMalformedLinksAndCredentialsDoNotLinkify() {
    for value in ["ftp://example.org/file", "javascript:alert(1)", "https://", "http:///missing", "https://user:secret@example.org/", "nothttps://example.org/", "https://example.org/file%zz", "https://example.org:99999/file", "https://example.org/\\file"] {
      let runs = SouthTextLinks.detect(in: [TextRun(text: value)])
      XCTAssertTrue(runs.compactMap(\.url).isEmpty, value)
      XCTAssertEqual(runs.map(\.text).joined(), value)
    }
  }
  func testLineBreaksAndExistingAnchorsAreNotJoinedIntoABareLink() throws {
    let blocks = try parse("https:<br>//example.org/ <a href='https://target.example/'>https:</a>//other.example/")
    let runs = blocks[0].runs
    XCTAssertEqual(runs.compactMap(\.url).map(\.host), ["target.example"])
  }
  func testDetectionIsIdempotentAndAnOversizedCandidateStaysLiteral() {
    let first = SouthTextLinks.detect(in: [TextRun(text: "https://example.org/file after")])
    XCTAssertEqual(SouthTextLinks.detect(in: first), first)
    let oversized = "https://example.org/" + String(repeating: "a", count: 8192)
    XCTAssertTrue(SouthTextLinks.detect(in: [TextRun(text: oversized)]).compactMap(\.url).isEmpty)
  }
}
