import Foundation
import XCTest
@testable import ForumCore

final class PostTextExportTests: XCTestCase {
  func testPreservesReadableParagraphsQuotesAndCodeWhitespace() {
    let blocks = [
      BodyBlock(kind: .paragraph, runs: [TextRun(text: "First ", bold: true), TextRun(text: "reply\nSecond line")]),
      BodyBlock(kind: .quote, children: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Quoted body")])], label: "Reader wrote:"),
      BodyBlock(kind: .code, label: "  code\n    indentation"),
      BodyBlock(kind: .spoiler, children: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Visible expanded body")])])
    ]
    XCTAssertEqual(PostTextExport.text(in: blocks), "First reply\nSecond line\n\nReader wrote:\nQuoted body\n\n  code\n    indentation\n\nVisible expanded body")
  }

  func testPreservesFullLinkTargetsWithoutDuplicatingURLLabels() {
    let url = URL(string: "https://example.org/long/source?file=one")!
    let link = BodyBlock(kind: .link, label: "Download source", url: url)
    let media = BodyBlock(kind: .media, label: url.absoluteString, url: url)
    XCTAssertEqual(PostTextExport.text(in: [link, media]), "Download source\n\(url)\n\n\(url)")
  }

  func testNeverExportsPurchaseTokensOrHiddenImageTransportMetadata() {
    let action = URL(string: "https://south-plus.net/job.php?action=buytopic&tid=20&pid=tpc&verify=synthetic")!
    let offer = SouthPurchaseOffer(threadID: "20", postID: "tpc", price: 0, action: action)
    let blocks = [BodyBlock(kind: .purchase, purchase: offer), BodyBlock(kind: .image, url: action),
                  BodyBlock(kind: .paragraph, runs: [TextRun(text: "   \n")])]
    XCTAssertEqual(PostTextExport.text(in: blocks), "")
  }
}
