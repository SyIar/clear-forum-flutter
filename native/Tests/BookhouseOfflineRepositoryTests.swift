import Foundation
import XCTest
@testable import ForumCore

final class BookhouseOfflineRepositoryTests: XCTestCase {
  private func chapter(_ number: Int) -> BookhouseChapter {
    BookhouseChapter(url: BookhouseSitePolicy.thread(String(number))!,
      title: "\u{3010}Novel\u{3011}\u{7B2C}\(number)\u{7AE0}", first: number, last: number)
  }
  private func book() throws -> BookhouseFollowedBook {
    let first = chapter(1)
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: ForumEntry(title: first.title, url: first.url, authorName: "Writer")))
    book.merge((2...8).map { let value = chapter($0); return ForumEntry(title: value.title, url: value.url, authorName: "Writer") }, checkedAt: Date())
    return book
  }
  private func page(_ chapter: BookhouseChapter) -> ForumPage {
    ForumPage(url: chapter.url, title: chapter.title, kind: .posts, entries: [],
      posts: [ForumPost(id: "main", author: "Writer", date: "", number: "", blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Cached text")])])], pageNumber: 1)
  }
  func testConcurrentSavesAndQueueExtensionsSurviveRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try book()
    let repository = BookhouseOfflineRepository(supportDirectory: directory, limit: 1_000_000)
    let pages = book.chapters.map(page)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for (chapter, page) in zip(book.chapters, pages) {
        group.addTask {
          _ = try await repository.enqueue(book, chapters: [chapter])
          _ = try await repository.store(page, book: book, preservingBookID: book.id)
        }
      }
      try await group.waitForAll()
    }
    let restored = BookhouseOfflineRepository(supportDirectory: directory, limit: 1_000_000)
    let snapshot = try await restored.snapshot()
    XCTAssertEqual(snapshot.plans.count, 1)
    XCTAssertEqual(Set(snapshot.plans[0].targets), Set(book.chapters.map(\.url)))
    XCTAssertEqual(snapshot.entries.count, book.chapters.count)
    for chapter in book.chapters {
      let cached = try await restored.page(chapter.url, book: book)
      XCTAssertEqual(cached?.url, chapter.url)
    }
  }
  func testCheckpointReconcilesAfterCacheClearAndRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try book(), first = chapter(1)
    let repository = BookhouseOfflineRepository(supportDirectory: directory, limit: 1_000_000)
    let queued = try await repository.enqueue(book, chapters: book.chapters)
    _ = try await repository.store(page(first), book: book, preservingBookID: book.id)
    _ = try await repository.advance(queued.plans[0].id, target: first.url)
    let restored = BookhouseOfflineRepository(supportDirectory: directory, limit: 1_000_000)
    let checkpoint = try await restored.snapshot()
    XCTAssertEqual(checkpoint.plans[0].completed, 1)
    _ = try await restored.clear()
    let reconciled = try await restored.reconcile(book.id)
    XCTAssertEqual(reconciled.bytes, 0)
    XCTAssertEqual(reconciled.plans[0].next, first.url)
    XCTAssertGreaterThan(reconciled.revision, checkpoint.revision)
  }
  func testDelayedCompletionDoesNotDeleteExtendedPlan() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try book(), first = chapter(1), second = chapter(2)
    let repository = BookhouseOfflineRepository(supportDirectory: directory, limit: 1_000_000)
    let queued = try await repository.enqueue(book, chapters: [first])
    let planID = queued.plans[0].id
    _ = try await repository.advance(planID, target: first.url)
    _ = try await repository.enqueue(book, chapters: [first, second])
    let extended = try await repository.finish(planID)
    XCTAssertEqual(extended.plans.count, 1)
    XCTAssertEqual(extended.plans[0].next, second.url)
    _ = try await repository.remove(planID)
    let replacement = try await repository.enqueue(book, chapters: [first])
    let delayed = try await repository.advance(planID, target: first.url)
    XCTAssertEqual(delayed.plans[0].id, replacement.plans[0].id)
    XCTAssertEqual(delayed.plans[0].completed, 0)
  }
  @MainActor func testCancelledSaveDoesNotWriteOrAdvanceQueue() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try book(), first = chapter(1), value = page(chapter(1))
    let repository = BookhouseOfflineRepository(supportDirectory: directory, limit: 1_000_000)
    let queued = try await repository.enqueue(book, chapters: [first])
    let save = Task {
      _ = try await repository.store(value, book: book, preservingBookID: book.id)
      _ = try await repository.advance(queued.plans[0].id, target: first.url)
    }
    save.cancel()
    do { try await save.value; XCTFail("A cancelled save should throw") }
    catch is CancellationError { }
    let snapshot = try await repository.snapshot()
    XCTAssertTrue(snapshot.entries.isEmpty)
    XCTAssertEqual(snapshot.plans[0].completed, 0)
  }
}
