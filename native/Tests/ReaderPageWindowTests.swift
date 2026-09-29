import Foundation
import XCTest
@testable import ForumCore

final class ReaderPageWindowTests: XCTestCase {
  private let simp = URL(string: "https://simpcity.cr/threads/sample.42/")!
  private let south = URL(string: "https://south-plus.net/read.php?tid-20-uid-123.html")!
  private func page(_ number: Int, root: URL? = nil, last: Int = 9) -> ForumPage {
    let address = SitePolicy.pageURL(root ?? simp, number: number)!
    return ForumPage(url: address, title: "Sample", kind: .posts, entries: [],
      posts: [ForumPost(id: "post-\(number)", author: "Reader", date: "", number: "#\(number)",
                       blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Page \(number)")])])],
      previous: number > 1 ? SitePolicy.pageURL(address, number: number - 1) : nil,
      next: number < last ? SitePolicy.pageURL(address, number: number + 1) : nil,
      pageNumber: number, loggedIn: true, totalPages: last)
  }
  func testPrependAndAppendKeepExistingPostAndBlockIdentities() {
    let initial = page(4)
    var window = ReaderPageWindow()
    window.reset(initial)
    XCTAssertTrue(window.insert(page(3), at: .previous, keeping: initial.url))
    XCTAssertTrue(window.insert(page(5), at: .next, keeping: initial.url))
    let combined = window.combined(active: initial)
    XCTAssertEqual(combined.posts.map(\.id), ["post-3", "post-4", "post-5"])
    XCTAssertEqual(combined.posts[1].blocks[0].id, initial.posts[0].blocks[0].id)
    XCTAssertEqual(combined.pageNumber, 4)
    XCTAssertEqual(window.page(containing: "post-3")?.pageNumber, 3)
    XCTAssertEqual(window.page(containing: "post-5")?.pageNumber, 5)
  }
  func testBoundariesAndOnePageThreadsHaveNoTarget() {
    var window = ReaderPageWindow()
    window.reset(page(1))
    XCTAssertNil(window.target(.previous))
    XCTAssertEqual(window.target(.next), page(2).url)
    window.reset(page(9))
    XCTAssertNil(window.target(.next))
    window.reset(page(1, last: 1))
    XCTAssertNil(window.target(.previous))
    XCTAssertNil(window.target(.next))
  }
  func testTargetsFollowWindowEdgesInsteadOfTheCurrentlyVisiblePage() {
    let initial = page(4)
    var window = ReaderPageWindow()
    window.reset(initial)
    XCTAssertTrue(window.insert(page(3), at: .previous, keeping: initial.url))
    XCTAssertTrue(window.insert(page(5), at: .next, keeping: initial.url))
    XCTAssertEqual(window.target(.previous), page(2).url)
    XCTAssertEqual(window.target(.next), page(6).url)
    XCTAssertFalse(window.insert(page(5), at: .next, keeping: initial.url))
    XCTAssertFalse(window.insert(page(7), at: .next, keeping: initial.url))
    XCTAssertEqual(window.pages.count, 3)
  }
  func testThreadAuthorAndForumFiltersCannotBeMixed() {
    var window = ReaderPageWindow()
    let filtered = page(2, root: south)
    window.reset(filtered)
    XCTAssertEqual(SouthSitePolicy.authorID(window.target(.previous)!), "123")
    XCTAssertFalse(window.insert(page(1, root: URL(string: "https://south-plus.net/read.php?tid-20.html")!), at: .previous, keeping: filtered.url))
    XCTAssertFalse(window.insert(page(1), at: .previous, keeping: filtered.url))
    XCTAssertTrue(window.insert(page(1, root: south), at: .previous, keeping: filtered.url))
    let forum = URL(string: "https://simpcity.cr/forums/example.12/?prefix_id=23")!
    window.reset(page(2, root: forum))
    XCTAssertFalse(window.insert(page(1, root: URL(string: "https://simpcity.cr/forums/example.12/?prefix_id=24")!), at: .previous, keeping: window.pages[0].url))
  }
  func testSouthLegacyAndQueryAliasesJoinTheSameWindow() {
    var window = ReaderPageWindow()
    let initial = page(2, root: south)
    window.reset(initial)
    var previous = page(1, root: south)
    previous.url = URL(string: "https://south-plus.net/read.php?uid=123&tid=20&page=1")!
    XCTAssertTrue(window.insert(previous, at: .previous, keeping: initial.url))
    XCTAssertEqual(window.pages.count, 2)
  }
  func testIncorrectResponseKindAndMisdirectedNextLinkAreRejected() {
    var window = ReaderPageWindow()
    let initial = page(3)
    window.reset(initial)
    var wrong = page(4); wrong.kind = .threads
    XCTAssertFalse(window.insert(wrong, at: .next, keeping: initial.url))
    var misleading = initial
    misleading.next = URL(string: "https://simpcity.cr/threads/another.99/page-4")!
    window.reset(misleading)
    XCTAssertNil(window.target(.next))
    XCTAssertEqual(window.pages[0].posts[0].blocks[0].id, initial.posts[0].blocks[0].id)
  }
  func testRepeatedRowsAcrossPagesAreRenderedOnlyOnce() {
    var window = ReaderPageWindow()
    var first = page(1)
    first.kind = .threads
    first.entries = [ForumEntry(title: "Pinned", url: simp, pinned: true)]
    first.posts = []
    window.reset(first)
    var second = page(2)
    second.kind = .threads
    second.entries = [ForumEntry(title: "Pinned", url: URL(string: simp.absoluteString + "?page=1")!, pinned: true),
                      ForumEntry(title: "Other", url: URL(string: "https://simpcity.cr/threads/other.43/")!)]
    second.posts = []
    XCTAssertTrue(window.insert(second, at: .next, keeping: first.url))
    XCTAssertEqual(window.combined(active: first).entries.map(\.title), ["Pinned", "Other"])
    window.reset(page(1))
    var duplicated = page(2); duplicated.posts.insert(window.pages[0].posts[0], at: 0)
    XCTAssertTrue(window.insert(duplicated, at: .next, keeping: window.pages[0].url))
    XCTAssertEqual(window.combined(active: page(1)).posts.map(\.id), ["post-1", "post-2"])
  }
  func testWindowEvictionKeepsVisiblePageAndAdjacentLinks() {
    var window = ReaderPageWindow(countLimit: 3)
    let initial = page(4)
    window.reset(initial)
    XCTAssertTrue(window.insert(page(3), at: .previous, keeping: initial.url))
    XCTAssertTrue(window.insert(page(5), at: .next, keeping: initial.url))
    XCTAssertTrue(window.insert(page(6), at: .next, keeping: page(5).url))
    XCTAssertEqual(window.pages.map(\.pageNumber), [4, 5, 6])
    XCTAssertEqual(window.target(.previous), page(3).url)
    XCTAssertTrue(window.insert(page(3), at: .previous, keeping: page(4).url))
    XCTAssertEqual(window.pages.map(\.pageNumber), [3, 4, 5])
    // If the user moved away while a request was in flight, keep their page.
    XCTAssertTrue(window.insert(page(6), at: .next, keeping: page(3).url))
    XCTAssertEqual(window.pages.map(\.pageNumber), [3, 4, 5])
  }
  func testPrependingARepeatedPostPreservesItsExistingMediaIdentity() {
    var initial = page(2)
    initial.posts[0].blocks = [BodyBlock(kind: .image, url: URL(string: "https://images.example/sample.png")!)]
    var window = ReaderPageWindow()
    window.reset(initial)
    var previous = page(1)
    previous.posts.append(ForumPost(id: initial.posts[0].id, author: "Reader", date: "", number: "#2",
                                   blocks: [BodyBlock(kind: .image, url: URL(string: "https://images.example/sample.png")!)]))
    XCTAssertTrue(window.insert(previous, at: .previous, keeping: initial.url))
    let merged = window.combined(active: initial)
    XCTAssertEqual(merged.posts.count, 2)
    XCTAssertEqual(merged.posts[1].blocks[0].id, initial.posts[0].blocks[0].id)
  }
  func testCostBudgetAlwaysKeepsTheActivePage() {
    let first = page(1)
    var window = ReaderPageWindow(countLimit: 5, costLimit: first.estimatedCacheCost + 1)
    window.reset(first)
    XCTAssertTrue(window.insert(page(2), at: .next, keeping: first.url))
    XCTAssertEqual(window.pages.count, 1)
    XCTAssertEqual(window.pages[0].url, first.url)
  }
  func testPurchaseUpdateReplacesOnlyItsSourcePage() {
    let initial = page(2, root: south)
    var window = ReaderPageWindow()
    window.reset(initial)
    var previous = page(1, root: south)
    let offer = SouthPurchaseOffer(threadID: "20", postID: "tpc", price: 0,
      action: URL(string: "https://south-plus.net/job.php?action=buytopic&tid=20&pid=tpc&verify=synthetic")!)
    previous.posts[0].blocks = [BodyBlock(kind: .purchase, purchase: offer)]
    XCTAssertTrue(window.insert(previous, at: .previous, keeping: initial.url))
    XCTAssertEqual(window.page(offering: offer)?.url, previous.url)
    var unlocked = previous
    unlocked.posts[0].blocks = [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Unlocked")])]
    window.replace(unlocked)
    XCTAssertTrue(window.page(for: previous.url)!.purchaseOffers.isEmpty)
    XCTAssertEqual(window.page(for: initial.url)?.posts[0].blocks[0].id, initial.posts[0].blocks[0].id)
    XCTAssertEqual(window.combined(active: initial).pageNumber, 2)
  }
  func testEdgeTriggerRequiresOverscrollDuringADragAndFiresOnce() {
    var trigger = ReaderEdgeTrigger()
    trigger.beginDrag()
    XCTAssertNil(trigger.update(topPull: 80, bottomPull: 0, interacting: false, previous: true, next: true))
    XCTAssertNil(trigger.update(topPull: 30, bottomPull: 0, interacting: true, previous: true, next: true))
    XCTAssertEqual(trigger.update(topPull: 60, bottomPull: 0, interacting: true, previous: true, next: true), .previous)
    XCTAssertNil(trigger.update(topPull: 90, bottomPull: 0, interacting: true, previous: true, next: true))
    XCTAssertNil(trigger.update(topPull: 0, bottomPull: 90, interacting: true, previous: true, next: true))
    trigger.beginDrag()
    XCTAssertEqual(trigger.update(topPull: 0, bottomPull: 60, interacting: true, previous: true, next: true), .next)
  }
  func testEdgeTriggerDoesNothingAtTheFirstOrLastPage() {
    var trigger = ReaderEdgeTrigger()
    trigger.beginDrag()
    XCTAssertNil(trigger.update(topPull: 90, bottomPull: 0, interacting: true, previous: false, next: true))
    XCTAssertNil(trigger.update(topPull: 0, bottomPull: 90, interacting: true, previous: true, next: false))
  }
}
