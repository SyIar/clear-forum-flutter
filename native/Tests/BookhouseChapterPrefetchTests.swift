import Foundation
import XCTest
@testable import ForumCore

final class BookhouseChapterPrefetchTests: XCTestCase {
  private func entry(_ number: Int, part: String = "") -> ForumEntry {
    ForumEntry(title: "\u{3010}Novel\u{3011}(\(number)\(part))",
      url: BookhouseSitePolicy.thread(String(number * 100 + (part == "\u{4E0B}" ? 2 : 1)))!, authorName: "Writer")
  }
  private func page(_ entry: ForumEntry, count: Int = 100) -> ForumPage {
    ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: "post", author: "Writer", date: "", number: "",
        blocks: (0..<count).map { BodyBlock(kind: .paragraph, runs: [TextRun(text: "Paragraph \($0)")]) })], pageNumber: 1)
  }
  private func book(_ entries: [ForumEntry]) -> BookhouseFollowedBook {
    var book = BookhouseFollowedBook(entry: entries[0])!
    book.merge(entries, checkedAt: Date())
    return book
  }

  func testThresholdUsesFinalPublicationAndLeavesReadingWindowUntouched() {
    let entries = [entry(1), entry(2), entry(3)]
    let book = book(entries)
    var window = BookhouseReadingWindow()
    window.reset(page(entries[0]), book: book)
    let initialIDs = window.paragraphs.map(\.id)
    XCTAssertNil(window.prefetchTarget(visibleIDs: [initialIDs[88]], book: book))
    XCTAssertEqual(window.prefetchTarget(visibleIDs: [initialIDs[89]], book: book)?.url, entries[1].url)
    XCTAssertEqual(window.paragraphs.map(\.id), initialIDs)
    XCTAssertNil(book.position)
    window.insert(page(entries[1]), at: .next, book: book)
    XCTAssertNil(window.prefetchTarget(visibleIDs: [initialIDs[99]], book: book))
    XCTAssertNil(window.prefetchTarget(visibleIDs: [window.paragraphs[188].id], book: book))
    XCTAssertEqual(window.prefetchTarget(visibleIDs: [window.paragraphs[189].id], book: book)?.url, entries[2].url)
    window.insert(page(entries[2]), at: .next, book: book)
    XCTAssertNil(window.prefetchTarget(visibleIDs: [window.paragraphs.last!.id], book: book))
  }

  func testSplitPublicationPrefetchesLowerPartBeforeNextChapter() {
    let entries = [entry(26, part: "\u{4E0A}"), entry(26, part: "\u{4E0B}"), entry(27)]
    let book = book(entries)
    var window = BookhouseReadingWindow()
    window.reset(page(entries[0], count: 10), book: book)
    XCTAssertEqual(window.prefetchTarget(visibleIDs: [window.paragraphs[8].id], book: book)?.url, entries[1].url)
    XCTAssertNil(window.prefetchTarget(visibleIDs: ["top", "bottom", "unknown"], book: book))
    window.insert(page(entries[1], count: 10), at: .next, book: book)
    XCTAssertEqual(window.prefetchTarget(visibleIDs: [window.paragraphs[18].id], book: book)?.url, entries[2].url)
  }

  @MainActor func testEdgeConsumerReusesOneSpeculativeRequest() async throws {
    let prefetch = BookhouseChapterPrefetch()
    let expected = page(entry(2))
    var requests = 0
    XCTAssertTrue(prefetch.start(expected.url) { requests += 1; return expected })
    XCTAssertFalse(prefetch.start(expected.url) { requests += 1; return expected })
    let result = await prefetch.take(expected.url)
    XCTAssertEqual(result?.url, expected.url)
    XCTAssertEqual(requests, 1)
    XCTAssertFalse(prefetch.start(expected.url) { requests += 1; return expected })
    let consumed = await prefetch.take(expected.url)
    XCTAssertNil(consumed)
  }

  @MainActor func testFailureDoesNotRepeatOnVisibilityUpdatesAndResetAllowsRetry() async {
    let prefetch = BookhouseChapterPrefetch()
    let expected = page(entry(2))
    var requests = 0
    prefetch.start(expected.url) { requests += 1; throw ReaderFailure.network }
    let failed = await prefetch.take(expected.url)
    XCTAssertNil(failed)
    for _ in 0..<20 { XCTAssertFalse(prefetch.start(expected.url) { requests += 1; return expected }) }
    XCTAssertEqual(requests, 1)
    prefetch.cancel()
    XCTAssertTrue(prefetch.start(expected.url) { requests += 1; return expected })
    let retried = await prefetch.take(expected.url)
    XCTAssertEqual(retried?.url, expected.url)
    XCTAssertEqual(requests, 2)
  }

  @MainActor func testCancellationDiscardsLateResultWithoutReplacingNewChapter() async {
    let prefetch = BookhouseChapterPrefetch()
    let old = page(entry(2)), replacement = page(entry(4))
    let started = expectation(description: "Old speculative request started")
    var continuation: CheckedContinuation<ForumPage, Never>?
    prefetch.start(old.url) {
      await withCheckedContinuation {
        continuation = $0
        started.fulfill()
      }
    }
    let consumer = Task { await prefetch.take(old.url) }
    await fulfillment(of: [started], timeout: 2)
    prefetch.cancel()
    prefetch.start(replacement.url) { replacement }
    continuation?.resume(returning: old)
    let obsolete = await consumer.value
    XCTAssertNil(obsolete)
    let current = await prefetch.take(replacement.url)
    XCTAssertEqual(current?.url, replacement.url)
  }
}
