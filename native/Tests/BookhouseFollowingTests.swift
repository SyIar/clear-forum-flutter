import Foundation
import XCTest
@testable import ForumCore

final class BookhouseFollowingTests: XCTestCase {
  private func entry(_ id: String, _ first: Int, _ last: Int, author: String = "Writer", name: String = "Novel") -> ForumEntry {
    ForumEntry(title: "\u{3010}\(name)\u{3011}\u{7B2C}\(first)-\(last)\u{7AE0}",
      url: BookhouseSitePolicy.thread(id)!, authorName: author)
  }
  func testArabicFullwidthAndChineseChapterRanges() throws {
    let arabic = try XCTUnwrap(BookhouseChapterTitle(entry("1", 454, 455).title))
    XCTAssertEqual(arabic.book, "Novel"); XCTAssertEqual(arabic.first, 454); XCTAssertEqual(arabic.last, 455)
    let fullwidth = try XCTUnwrap(BookhouseChapterTitle("\u{3010}Novel\u{3011}\u{FF08}\u{FF11}\u{FF0D}\u{FF11}\u{FF11}\u{FF09}"))
    XCTAssertEqual(fullwidth.last, 11)
    XCTAssertEqual(BookhouseChapterTitle.number("\u{56DB}\u{767E}\u{4E94}\u{5341}\u{56DB}"), 454)
    XCTAssertEqual(BookhouseChapterTitle.number("\u{4E00}\u{3007}\u{4E8C}"), 102)
    XCTAssertNil(BookhouseChapterTitle(entry("1", 10, 2).title))
    XCTAssertNil(BookhouseChapterTitle("Novel discussion 2026"))
    XCTAssertNil(BookhouseChapterTitle.number("100001"))
  }
  func testMatchingUsesBookNameAndOriginalPostingAccount() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", 1, 2)))
    XCTAssertTrue(book.matches(entry("2", 3, 4)))
    XCTAssertFalse(book.matches(entry("3", 3, 4, author: "Another writer")))
    XCTAssertFalse(book.matches(entry("4", 3, 4, name: "Novel sequel")))
    var candidate = entry("5", 3, 4); candidate.authorName = nil
    XCTAssertFalse(book.matches(candidate))
    book.authorID = "10"; candidate.authorName = "Writer"; candidate.authorID = "11"
    XCTAssertFalse(book.matches(candidate))
  }
  func testCatalogSortsDeduplicatesAndResolvesOverlappingBundles() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", 59, 62)))
    let rows = [entry("2", 60, 82), entry("3", 83, 99), entry("1", 59, 62), entry("4", 1, 58)]
    book.merge(rows + rows, checkedAt: Date())
    XCTAssertEqual(book.chapters.map(\.first), [1, 59, 60, 83])
    XCTAssertEqual(book.chapter(containing: 60)?.url, entry("1", 59, 62).url)
    XCTAssertEqual(book.chapter(containing: 63)?.url, entry("2", 60, 82).url)
    XCTAssertNil(book.chapter(containing: 100))
    XCTAssertNil(book.chapter(containing: 59, excluding: entry("1", 59, 62).url))
    XCTAssertEqual(book.chapter(containing: 60, excluding: entry("1", 59, 62).url)?.first, 60)
  }
  func testCatalogRefreshPreservesActualReadingPositionAndDetectsNewChapters() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", 1, 2)))
    book.merge([entry("2", 3, 4)], checkedAt: Date())
    XCTAssertFalse(book.updated); XCTAssertNil(book.maximumRead)
    book.record(url: entry("1", 1, 2).url, chapter: 1, paragraph: 5)
    let position = book.position
    book.merge([entry("3", 5, 6)], checkedAt: Date())
    XCTAssertTrue(book.updated); XCTAssertEqual(book.maximumRead, 1); XCTAssertEqual(book.position, position)
    book.record(url: entry("3", 5, 6).url, chapter: 6, paragraph: 1)
    XCTAssertFalse(book.updated)
    book.record(url: entry("1", 1, 2).url, chapter: 1, paragraph: 8)
    XCTAssertEqual(book.position?.chapter, 1); XCTAssertEqual(book.maximumRead, 6)
    book.record(url: entry("1", 1, 2).url, chapter: 200, paragraph: 0)
    XCTAssertEqual(book.position?.chapter, 1)
  }
  func testChapterHeadingAnchorsDoNotTreatWholePublicationAsRead() throws {
    let book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", 454, 455)))
    let blocks = ["\u{7B2C}454\u{7AE0} Heading", "A paragraph mentioning \u{7B2C}455\u{7AE0}",
      "Body text", "\u{7B2C}455\u{7AE0} Next", "Ending"]
      .map { BodyBlock(kind: .paragraph, runs: [TextRun(text: $0)]) }
    let anchors = BookhouseChapterAnchors(blocks: blocks, chapter: book.chapters[0])
    XCTAssertEqual(anchors.paragraph(for: 455), 3)
    XCTAssertEqual(anchors.chapter(at: 2, fallback: 454), 454)
    XCTAssertEqual(anchors.chapter(at: 4, fallback: 454), 455)
    XCTAssertNil(anchors.paragraph(for: 456))
  }
  func testReaderRejectsWrongAccountEvenWhenNamesMatch() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", 1, 2)))
    book.authorID = "10"
    var page = ForumPage(url: book.seed, title: entry("1", 1, 2).title, kind: .posts, entries: [],
      posts: [ForumPost(id: "1", author: "Writer", date: "", number: "", blocks: [], authorID: "11")], pageNumber: 1)
    XCTAssertFalse(book.accepts(page))
    page.posts[0].authorID = "10"
    XCTAssertTrue(book.accepts(page))
  }
  func testLibraryMigrationAndRelaunchKeepBookAndParagraphProgress() throws {
    let old = Data(#"{"version":1,"site":"bookhouse","bookmarks":[],"recent":[]}"#.utf8)
    var library = try JSONDecoder().decode(LibraryDocument.self, from: old)
    XCTAssertTrue(library.followedBooks.isEmpty)
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", 454, 455)))
    book.record(url: book.seed, chapter: 454, paragraph: 25)
    library.followedBooks[book.id] = book
    let restored = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(library))
    XCTAssertEqual(restored.followedBooks[book.id], book)
    XCTAssertEqual(restored.followedBooks[book.id]?.position?.paragraph, 25)
  }
}
