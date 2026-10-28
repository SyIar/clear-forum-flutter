import Foundation
import XCTest
@testable import ForumCore

final class BookhouseOfflinePlanTests: XCTestCase {
  private func chapter(_ number: Int) -> BookhouseChapter {
    BookhouseChapter(url: BookhouseSitePolicy.thread(String(number))!,
      title: "\u{3010}Novel\u{3011}\u{7B2C}\(number)\u{7AE0}", first: number, last: number)
  }
  private func book() throws -> BookhouseFollowedBook {
    let first = chapter(1)
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: ForumEntry(title: first.title, url: first.url, authorName: "Writer")))
    book.merge((2...3).map { let value = chapter($0); return ForumEntry(title: value.title, url: value.url, authorName: "Writer") }, checkedAt: Date())
    return book
  }
  private func page(_ chapter: BookhouseChapter) -> ForumPage {
    ForumPage(url: chapter.url, title: chapter.title, kind: .posts, entries: [],
      posts: [ForumPost(id: "main", author: "Writer", date: "", number: "", blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: String(repeating: "Text ", count: 100))])])], pageNumber: 1)
  }
  func testRestartPreservesCursorAndExtendingTaskDoesNotDuplicateOrSkip() throws {
    var plan = BookhouseOfflinePlan(bookID: "book", chapters: [chapter(1), chapter(2), chapter(2)])
    plan.advance(chapter(2).url)
    XCTAssertEqual(plan.completed, 0)
    plan.advance(chapter(1).url)
    var restored = try JSONDecoder().decode(BookhouseOfflinePlan.self, from: JSONEncoder().encode(plan))
    XCTAssertEqual(restored.id, plan.id)
    XCTAssertEqual(restored.next, chapter(2).url)
    restored.include([chapter(1), chapter(2), chapter(3)])
    XCTAssertEqual(restored.targets, (1...3).map { chapter($0).url })
    restored.advance(chapter(2).url); restored.advance(chapter(3).url)
    XCTAssertNil(restored.next)
    XCTAssertTrue(restored.valid)
    restored.reconcile { $0 != chapter(2).url }
    XCTAssertEqual(restored.completed, 1)
    XCTAssertEqual(restored.next, chapter(2).url)
    restored.reconcile { _ in false }
    XCTAssertEqual(restored.completed, 0)
  }
  func testCacheWrittenBeforeQueueCheckpointCanBeReusedAfterRestart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try book()
    let plan = BookhouseOfflinePlan(bookID: book.id, chapters: book.chapters)
    let cache = try BookhouseOfflineCache(directory: directory)
    try cache.store(page(chapter(1)), book: book, preservingBookID: book.id)
    let restoredCache = try BookhouseOfflineCache(directory: directory)
    var restoredPlan = try JSONDecoder().decode(BookhouseOfflinePlan.self, from: JSONEncoder().encode(plan))
    let next = try XCTUnwrap(restoredPlan.next)
    XCTAssertNotNil(try restoredCache.page(next, book: book))
    restoredPlan.advance(next)
    XCTAssertEqual(restoredPlan.next, chapter(2).url)
    try restoredCache.clear()
    restoredPlan.reconcile { restoredCache.contains($0, bookID: book.id) }
    XCTAssertEqual(restoredPlan.next, chapter(1).url)
  }
  func testWholeBookCacheDoesNotEvictItsEarlierChaptersToPretendCompletion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try book()
    let first = page(chapter(1)), second = page(chapter(2))
    let size = max(try JSONEncoder().encode(first).count, try JSONEncoder().encode(second).count)
    let cache = try BookhouseOfflineCache(directory: directory, limit: size + 20)
    try cache.store(first, book: book, preservingBookID: book.id)
    XCTAssertThrowsError(try cache.store(second, book: book, preservingBookID: book.id)) { error in
      XCTAssertTrue(error is BookhouseOfflineFailure)
    }
    XCTAssertTrue(cache.contains(first.url, bookID: book.id))
    XCTAssertFalse(cache.contains(second.url, bookID: book.id))
    let restored = try BookhouseOfflineCache(directory: directory, limit: size + 20)
    XCTAssertTrue(restored.contains(first.url, bookID: book.id))
    try restored.setLimit(size * 3)
    try restored.store(second, book: book, preservingBookID: book.id)
    XCTAssertTrue(restored.contains(first.url, bookID: book.id))
    XCTAssertTrue(restored.contains(second.url, bookID: book.id))
    XCTAssertThrowsError(try restored.setLimit(size, preservingBookID: book.id))
    XCTAssertEqual(restored.limit, size * 3)
    XCTAssertTrue(restored.contains(first.url, bookID: book.id))
    XCTAssertTrue(restored.contains(second.url, bookID: book.id))
  }
}
