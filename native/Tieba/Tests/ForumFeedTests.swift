import XCTest
@testable import TiebaCore

final class ForumFeedTests: XCTestCase {
  private func thread(_ id: String, pinned: Bool = false, title: String = "Thread") -> ThreadSummary {
    ThreadSummary(["id": id, "title": title, "is_top": pinned ? 1 : 0])
  }
  private func page(_ number: Int, _ ids: [String], more: Bool = true) -> PageResult<ThreadSummary> {
    PageResult(items: ids.map { thread($0) }, page: number, hasMore: more, forum: Forum(raw: ["id": "9", "name": "Forum"]))
  }

  func testReturnFromDetailKeepsPagesAndCurrentThreadWithoutAnotherLoad() {
    var feed = ForumFeed(), gate = ForumFeedLoadGate()
    let initial = ForumFeedRequest()
    feed.apply(page(1, ["11", "12"])); gate.finish(initial)
    let next = ForumFeedRequest(page: 2, replacingAll: false, moveToPage: false)
    feed.apply(page(2, ["21", "22"])); gate.finish(next)
    feed.showThread("22")
    // Covering the destination leaves both the request and feed intact.
    XCTAssertFalse(gate.needsLoad(next))
    XCTAssertEqual(feed.currentPage, 2)
    XCTAssertEqual(feed.items.map(\.id), ["11", "12", "21", "22"])
    XCTAssertEqual(feed.firstThread(on: 2), "21")
    XCTAssertTrue(gate.needsLoad(ForumFeedRequest(page: 2, replacingAll: false, moveToPage: false)))
  }

  func testAppendPreservesOrderAndDeduplicatesMovingThreadsAndPins() {
    var feed = ForumFeed()
    var first = page(1, ["11", "12", "12"])
    first.items.insert(thread("99", pinned: true), at: 0)
    feed.apply(first)
    var next = page(2, ["12", "21", "21"])
    next.items.insert(thread("99", pinned: true, title: "Updated pin"), at: 0)
    feed.apply(next)
    XCTAssertEqual(feed.items.map(\.id), ["11", "12", "21"])
    XCTAssertEqual(feed.pages[0].items.map(\.id), ["11", "12"])
    XCTAssertEqual(feed.pages[1].items.map(\.id), ["21"])
    XCTAssertEqual(feed.pinned.map(\.title), ["Updated pin"])
    XCTAssertEqual(feed.currentPage, 1, "Prefetch must not advance the displayed page.")
    feed.showThread("21")
    XCTAssertEqual(feed.currentPage, 2)
  }

  func testPrependRetainsExistingThreadOwnershipAndVisiblePage() {
    var feed = ForumFeed()
    feed.apply(page(3, ["31", "32"]))
    XCTAssertEqual(feed.previousPage, 2)
    feed.apply(page(2, ["21", "31"]))
    XCTAssertEqual(feed.items.map(\.id), ["21", "31", "32"])
    XCTAssertEqual(feed.firstThread(on: 3), "31")
    XCTAssertEqual(feed.currentPage, 3)
  }

  func testExplicitRefreshReplacesOnlyOnePage() {
    var feed = ForumFeed()
    feed.apply(page(1, ["11", "12"]))
    feed.apply(page(2, ["21", "22"]))
    feed.apply(page(3, ["31"]))
    feed.showThread("22")
    feed.apply(page(2, ["23", "21", "31"]))
    XCTAssertEqual(feed.pages.map(\.number), [1, 2, 3])
    XCTAssertEqual(feed.items.map(\.id), ["11", "12", "23", "21", "31"])
    XCTAssertEqual(feed.currentPage, 2)
  }

  func testQueryResetDropsPreviousResultsAndPins() {
    var feed = ForumFeed()
    var initial = page(1, ["11"])
    initial.items.append(thread("99", pinned: true))
    feed.apply(initial); feed.apply(page(2, ["21"])); feed.showPage(2)
    feed.apply(page(1, ["51"], more: false), replacingAll: true)
    XCTAssertEqual(feed.items.map(\.id), ["51"])
    XCTAssertTrue(feed.pinned.isEmpty)
    XCTAssertEqual(feed.currentPage, 1)
    XCTAssertNil(feed.nextPage)
  }

  func testEmptyLastPageDoesNotReloadOrOfferAnotherPage() {
    var feed = ForumFeed(), gate = ForumFeedLoadGate()
    let request = ForumFeedRequest()
    feed.apply(page(1, [], more: false)); gate.finish(request)
    XCTAssertTrue(feed.contains(1))
    XCTAssertFalse(gate.needsLoad(request))
    XCTAssertNil(feed.nextPage)
    XCTAssertNil(feed.previousPage)
    XCTAssertFalse(feed.canGoForward)
  }

  func testLoadedNextPageRemainsReachableWhenLastPageHasNoMore() {
    var feed = ForumFeed()
    feed.apply(page(1, ["11"]))
    feed.apply(page(2, ["21"], more: false))
    XCTAssertTrue(feed.canGoForward)
    feed.showPage(2)
    XCTAssertFalse(feed.canGoForward)
    feed.showPage(1)
    XCTAssertTrue(feed.canGoForward)
  }

  func testNonadjacentOrInvalidResponseCannotReplaceFeed() {
    var feed = ForumFeed()
    feed.apply(page(1, ["11"]))
    XCTAssertFalse(feed.apply(page(7, ["71"])))
    XCTAssertFalse(feed.apply(page(0, ["01"]), replacingAll: true))
    XCTAssertEqual(feed.items.map(\.id), ["11"])
    XCTAssertEqual(feed.currentPage, 1)
  }

  func testFirstPageRefreshRemovesOldPinAndPromotesNewPinWithoutDuplicates() {
    var feed = ForumFeed()
    var initial = page(1, ["11"])
    initial.items.append(thread("99", pinned: true))
    feed.apply(initial); feed.apply(page(2, ["21"]))
    var refreshed = page(1, ["99", "11"])
    refreshed.items.append(thread("21", pinned: true))
    feed.apply(refreshed)
    XCTAssertEqual(feed.pinned.map(\.id), ["21"])
    XCTAssertEqual(feed.items.map(\.id), ["99", "11"])
  }

  func testEdgeRequiresUserScrollAndOnlyFiresOncePerDrag() {
    var trigger = ForumFeedEdgeTrigger()
    XCTAssertNil(trigger.update(topPull: 0, remaining: 20, interacting: false, previous: false, next: true))
    trigger.beginDrag()
    XCTAssertEqual(trigger.update(topPull: 0, remaining: 200, interacting: true, previous: false, next: true), .next)
    XCTAssertNil(trigger.update(topPull: 0, remaining: 0, interacting: true, previous: false, next: true))
    trigger.beginDrag()
    XCTAssertEqual(trigger.update(topPull: 0, remaining: 0, interacting: true, previous: false, next: true), .next)
  }

  func testTopPullDoesNotRefreshOrLoadNextOnAShortFirstPage() {
    var trigger = ForumFeedEdgeTrigger()
    trigger.beginDrag()
    XCTAssertNil(trigger.update(topPull: 70, remaining: 70, interacting: true, previous: false, next: true))
    XCTAssertEqual(trigger.update(topPull: 70, remaining: 70, interacting: true, previous: true, next: true), .previous)
    trigger.beginDrag()
    XCTAssertNil(trigger.update(topPull: 0, remaining: 0, interacting: true, previous: false, next: false))
  }
}
