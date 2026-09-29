import Foundation
import XCTest
@testable import ForumCore

final class PurchasePageUpdateTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private func text(_ value: String) -> BodyBlock { BodyBlock(kind: .paragraph, runs: [TextRun(text: value)]) }
  private func image(_ filename: String) -> BodyBlock { BodyBlock(kind: .image, url: URL(string: "https://images.example/\(filename)")) }
  private func gate(_ token: String) -> BodyBlock {
    BodyBlock(kind: .purchase, purchase: SouthPurchaseOffer(threadID: "20", postID: "tpc", price: 0,
      action: URL(string: "https://south-plus.net/job.php?action=buytopic&tid=20&pid=tpc&verify=\(token)")!))
  }
  private func page(_ blocks: [BodyBlock]) -> ForumPage {
    ForumPage(url: url, title: "Sample", kind: .posts, entries: [],
      posts: [ForumPost(id: "post_tpc", author: "Author", date: "", number: "#0", blocks: blocks),
              ForumPost(id: "post_123", author: "Reader", date: "", number: "#1", blocks: [image("reply.png")])],
      pageNumber: 1, loggedIn: true)
  }
  func testUnlockPreservesMediaBeforeAndAfterTheExpandedPurchaseRegion() {
    let old = page([image("before.png"), gate("old"), image("after.png")])
    let fresh = page([image("before.png"), text("Unlocked"), image("new.png"), image("after.png")])
    let merged = fresh.preservingPurchaseContent(from: old)
    XCTAssertEqual(merged.posts[0].blocks[0].id, old.posts[0].blocks[0].id)
    XCTAssertEqual(merged.posts[0].blocks[3].id, old.posts[0].blocks[2].id)
    XCTAssertEqual(merged.posts[0].blocks[1].id, fresh.posts[0].blocks[1].id)
    XCTAssertEqual(merged.posts[0].blocks[2].id, fresh.posts[0].blocks[2].id)
    XCTAssertEqual(merged.posts[1].blocks[0].id, old.posts[1].blocks[0].id)
    XCTAssertTrue(merged.purchaseOffers.isEmpty)
  }
  func testChangedImageOrTokenIsNeverReplacedWithItsStaleVersion() {
    let old = page([image("old.png"), gate("old")])
    let fresh = page([image("new.png"), gate("new")])
    let merged = fresh.preservingPurchaseContent(from: old)
    XCTAssertEqual(merged.posts[0].blocks.map(\.id), fresh.posts[0].blocks.map(\.id))
    XCTAssertEqual(merged.purchaseOffers.first?.action, fresh.purchaseOffers.first?.action)
  }
  func testSurroundingSpoilerKeepsIdentityWhileItsBodyChanges() {
    let old = page([BodyBlock(kind: .spoiler, children: [text("Before"), gate("old"), image("after.png")], label: "Details")])
    let fresh = page([BodyBlock(kind: .spoiler, children: [text("Before"), text("Unlocked"), image("after.png")], label: "Details")])
    let merged = fresh.preservingPurchaseContent(from: old)
    XCTAssertEqual(merged.posts[0].blocks[0].id, old.posts[0].blocks[0].id)
    XCTAssertEqual(merged.posts[0].blocks[0].children[2].id, old.posts[0].blocks[0].children[2].id)
    XCTAssertEqual(merged.posts[0].blocks[0].children[1].runs.first?.text, "Unlocked")
  }
  func testDifferentPageOrAuthorFilterDoesNotReuseContentIdentity() {
    let old = page([image("same.png")])
    for address in ["https://south-plus.net/read.php?tid-20-page-2.html", "https://south-plus.net/read.php?tid-20-uid-123.html"] {
      var fresh = page([image("same.png")]); fresh.url = URL(string: address)!
      let merged = fresh.preservingPurchaseContent(from: old)
      XCTAssertEqual(merged.posts[0].blocks[0].id, fresh.posts[0].blocks[0].id)
      XCTAssertNotEqual(merged.posts[0].blocks[0].id, old.posts[0].blocks[0].id)
    }
  }
  func testFreshMetadataAndPostOrderAreRetained() {
    let old = page([text("Unchanged")])
    var fresh = page([text("Unchanged")])
    fresh.posts.reverse()
    fresh.title = "Updated title"
    fresh.totalPages = 8
    fresh.posts[1].author = "Updated author"
    let merged = fresh.preservingPurchaseContent(from: old)
    XCTAssertEqual(merged.title, "Updated title")
    XCTAssertEqual(merged.totalPages, 8)
    XCTAssertEqual(merged.posts[1].author, "Updated author")
    XCTAssertEqual(merged.posts[0].id, "post_123")
    XCTAssertEqual(merged.posts[1].blocks[0].id, old.posts[0].blocks[0].id)
  }
}
