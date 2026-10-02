import Foundation
import XCTest
@testable import ForumCore

final class BookhouseOfflineSearchTests: XCTestCase {
  private func entry(_ id: Int, name: String = "Novel") -> ForumEntry {
    ForumEntry(title: "\u{3010}\(name)\u{3011}\u{7B2C}1-2\u{7AE0}",
      url: BookhouseSitePolicy.thread(String(id))!, authorName: "Writer")
  }
  private func page(_ entry: ForumEntry, blocks: [BodyBlock]) -> ForumPage {
    ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: "main", author: "Writer", date: "", number: "", blocks: blocks)], pageNumber: 1)
  }
  private func paragraph(_ text: String) -> BodyBlock { BodyBlock(kind: .paragraph, runs: [TextRun(text: text)]) }

  func testGlobalSearchJoinsStyledRunsAndLocatesChapterAndParagraphAfterRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = entry(1), second = entry(2, name: "Another")
    let books = try [first, second].map { try XCTUnwrap(BookhouseFollowedBook(entry: $0)) }
    let cache = try BookhouseOfflineCache(directory: directory)
    try cache.store(page(first, blocks: [paragraph("\u{7B2C}1\u{7AE0} Beginning"), paragraph("Unrelated"),
      paragraph("\u{7B2C}2\u{7AE0} Continuation"),
      BodyBlock(kind: .paragraph, runs: [TextRun(text: "The Need", bold: true), TextRun(text: "le appears here.")])]), book: books[0])
    try cache.store(page(second, blocks: [paragraph("A NEEDLE in another book.")]), book: books[1])
    let restored = try BookhouseOfflineCache(directory: directory)
    let dates = restored.entries.map(\.accessed)
    let result = try BookhouseOfflineSearch.search(" needle ", documents: restored.searchDocuments(books: books))
    XCTAssertEqual(result.matches.count, 2)
    let match = try XCTUnwrap(result.matches.first { $0.bookID == books[0].id })
    XCTAssertEqual(match.chapter, 2)
    XCTAssertEqual(match.paragraph, 3)
    XCTAssertEqual(match.url, first.url)
    XCTAssertEqual(match.snippet, "The Needle appears here.")
    XCTAssertEqual(match.query, "needle")
    XCTAssertEqual(restored.entries.map(\.accessed), dates)
    XCTAssertNil(books[0].position)
    XCTAssertEqual(restored.searchDocuments(books: [books[0]]).count, 1)
    XCTAssertTrue(restored.searchDocuments(books: []).isEmpty)
  }

  func testUnicodeNestedTextAndBoundedSnippetsExcludeMediaLabels() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = entry(1), book = try XCTUnwrap(BookhouseFollowedBook(entry: source))
    let cache = try BookhouseOfflineCache(directory: directory)
    let word = "\u{661F}\u{5149}"
    try cache.store(page(source, blocks: [paragraph(String(repeating: "a", count: 100) + word + String(repeating: "z", count: 100)),
      BodyBlock(kind: .quote, children: [paragraph("Caf\u{E9} \u{FF34}\u{FF25}\u{FF33}\u{FF34}")]),
      BodyBlock(kind: .image, runs: [TextRun(text: word)], label: word)]), book: book)
    let documents = cache.searchDocuments(books: [book])
    let result = try BookhouseOfflineSearch.search(word, documents: documents)
    XCTAssertEqual(result.matches.count, 1)
    XCTAssertTrue(result.matches[0].snippet.hasPrefix("\u{2026}"))
    XCTAssertTrue(result.matches[0].snippet.hasSuffix("\u{2026}"))
    XCTAssertLessThan(result.matches[0].snippet.count, 130)
    XCTAssertEqual(try BookhouseOfflineSearch.search("cafe test", documents: documents).matches.first?.paragraph, 1)
  }

  func testSearchLimitAndBlankQuery() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = entry(1), book = try XCTUnwrap(BookhouseFollowedBook(entry: source))
    let cache = try BookhouseOfflineCache(directory: directory)
    try cache.store(page(source, blocks: (0..<5).map { paragraph("Match \($0)") }), book: book)
    let documents = cache.searchDocuments(books: [book])
    let limited = try BookhouseOfflineSearch.search("match", documents: documents, limit: 2)
    XCTAssertEqual(limited.matches.map(\.paragraph), [0, 1])
    XCTAssertTrue(limited.truncated)
    XCTAssertFalse(try BookhouseOfflineSearch.search("match", documents: documents, limit: 5).truncated)
    XCTAssertTrue(try BookhouseOfflineSearch.search(" \n ", documents: documents).matches.isEmpty)
    XCTAssertTrue(try BookhouseOfflineSearch.search("missing", documents: documents).matches.isEmpty)
  }

  func testRemovedAndCorruptFilesDoNotBreakOtherResultsAndAuthorIsRevalidated() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = entry(1), other = entry(2, name: "Other")
    let book = try XCTUnwrap(BookhouseFollowedBook(entry: source)), otherBook = try XCTUnwrap(BookhouseFollowedBook(entry: other))
    let cache = try BookhouseOfflineCache(directory: directory)
    try cache.store(page(source, blocks: [paragraph("Needle")]), book: book)
    try cache.store(page(other, blocks: [paragraph("Needle")]), book: otherBook)
    let documents = cache.searchDocuments(books: [book, otherBook])
    let file = try XCTUnwrap(documents.first { $0.book.id == book.id }?.file)
    var wrong = page(source, blocks: [paragraph("Needle")]); wrong.posts[0].author = "Someone else"
    try JSONEncoder().encode(wrong).write(to: file)
    XCTAssertEqual(try BookhouseOfflineSearch.search("Needle", documents: documents).matches.map(\.bookID), [otherBook.id])
    try Data("invalid".utf8).write(to: file)
    let result = try BookhouseOfflineSearch.search("Needle", documents: documents)
    XCTAssertEqual(result.matches.count, 1)
    XCTAssertEqual(result.unreadablePages, 1)
    try cache.clear()
    let removed = try BookhouseOfflineSearch.search("Needle", documents: documents)
    XCTAssertTrue(removed.matches.isEmpty)
    XCTAssertEqual(removed.unreadablePages, 2)
  }
}
