import Foundation
import XCTest
@testable import ForumCore

final class ReaderUXPersistenceTests: XCTestCase {
  private func entry(_ id: Int, chapter: Int) -> ForumEntry {
    ForumEntry(title: "\u{3010}Novel\u{3011}\u{7B2C}\(chapter)\u{7AE0}", url: BookhouseSitePolicy.thread(String(id))!, authorName: "Writer")
  }
  private func page(_ entry: ForumEntry) -> ForumPage {
    ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: "main", author: "Writer", date: "", number: "", blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Readable text")])])], pageNumber: 1)
  }
  func testOfflineCacheSurvivesRelaunchValidatesAuthorAndPreservesBlockIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let book = try XCTUnwrap(BookhouseFollowedBook(entry: entry(1, chapter: 1)))
    let original = page(entry(1, chapter: 1))
    let cache = try BookhouseOfflineCache(directory: directory)
    try cache.store(original, book: book)
    let restored = try BookhouseOfflineCache(directory: directory)
    XCTAssertTrue(restored.contains(book.seed, bookID: book.id))
    XCTAssertEqual(try restored.page(book.seed, book: book)?.posts.first?.blocks.first?.id, original.posts.first?.blocks.first?.id)
    var wrong = original; wrong.posts[0].author = "Other writer"
    XCTAssertThrowsError(try restored.store(wrong, book: book))
    try restored.clear()
    XCTAssertEqual(restored.bytes, 0)
    XCTAssertNil(try restored.page(book.seed, book: book))
    XCTAssertFalse(book.chapters.isEmpty)
  }
  func testOfflineLimitEvictsLeastRecentlyReadAndDoesNotCrossBooks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry(1, chapter: 1)))
    book.merge([entry(2, chapter: 2)], checkedAt: Date())
    let cache = try BookhouseOfflineCache(directory: directory)
    try cache.store(page(entry(1, chapter: 1)), book: book)
    try cache.store(page(entry(2, chapter: 2)), book: book)
    _ = try cache.page(entry(1, chapter: 1).url, book: book)
    let firstSize = try JSONEncoder().encode(page(entry(1, chapter: 1))).count
    try cache.setLimit(firstSize + 20)
    XCTAssertTrue(cache.contains(entry(1, chapter: 1).url, bookID: book.id))
    XCTAssertFalse(cache.contains(entry(2, chapter: 2).url, bookID: book.id))
    XCTAssertFalse(cache.contains(entry(1, chapter: 1).url, bookID: "other"))
    XCTAssertLessThanOrEqual(cache.bytes, cache.limit)
  }
  func testCacheTargetsIncludeCurrentAndNextFiveChapterNumbers() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry(1, chapter: 1)))
    book.merge((2...10).map { entry($0, chapter: $0) }, checkedAt: Date())
    book.record(url: entry(3, chapter: 3).url, chapter: 3, paragraph: 9)
    XCTAssertEqual(book.offlineTargets.map(\.first), [3, 4, 5, 6, 7, 8])
    XCTAssertEqual(book.position?.paragraph, 9)
  }
  func testAppearanceClampsInvalidValues() {
    var value = ReadingAppearance()
    value.fontSize = .nan; value.lineSpacing = 100; value.paragraphSpacing = -1; value.margin = .infinity
    XCTAssertEqual(value.normalized.fontSize, 20)
    XCTAssertEqual(value.normalized.lineSpacing, 18)
    XCTAssertEqual(value.normalized.paragraphSpacing, 6)
    XCTAssertEqual(value.normalized.margin, 18)
  }
  func testOnlyCompleteResumedResponsesAreAccepted() {
    XCTAssertEqual(DownloadQueuePolicy.completedResponse(status: 206, contentRange: "bytes 50-99/100", bytes: 100, resumed: true), 200)
    for value in ["bytes 50-99/100", "garbage/100", "bytes 100-99/100", "bytes 0-49/100"] {
      XCTAssertEqual(DownloadQueuePolicy.completedResponse(status: 206, contentRange: value, bytes: 50, resumed: true), 206)
    }
    XCTAssertEqual(DownloadQueuePolicy.completedResponse(status: 206, contentRange: "bytes 0-99/100", bytes: 100, resumed: false), 206)
    XCTAssertTrue(DownloadQueuePolicy.safePath(["Album", "file.zip"]))
    for path in [["..", "file"], ["/tmp"], ["a\\b"], ["."], [String]()] { XCTAssertFalse(DownloadQueuePolicy.safePath(path)) }
  }
  func testQueueSerializationPreservesIdentityOrderAndDeduplication() throws {
    let file = GofileEntry(id: "f", name: "file.zip", folder: false, size: 42, mime: "application/zip", link: nil, thumbnail: nil, unavailable: false)
    let listing = GofileListing(id: "root", title: "Album", entries: [file, file], page: 1, pages: 1)
    let plan = try GofileBatchPlan(listing: listing)
    var restored = try JSONDecoder().decode(GofileBatchPlan.self, from: JSONEncoder().encode(plan))
    XCTAssertEqual(restored.pending.count, 1); XCTAssertEqual(restored.next?.id, plan.next?.id)
    XCTAssertEqual(restored.next?.entry.size, 42); restored.advance(); XCTAssertNil(restored.next)
    let hosted = HostedFileEntry(pageURL: URL(string: "https://filester.me/d/example")!, name: "sample.zip")
    let hostedPlan = try HostedBatchPlan(HostedFileListing(url: hosted.pageURL, title: "Sample", entries: [hosted, hosted]))
    let restoredHosted = try JSONDecoder().decode(HostedBatchPlan.self, from: JSONEncoder().encode(hostedPlan))
    XCTAssertEqual(restoredHosted.pending.count, 1)
    XCTAssertEqual(restoredHosted.pending.first?.id, hostedPlan.pending.first?.id)
  }
}
