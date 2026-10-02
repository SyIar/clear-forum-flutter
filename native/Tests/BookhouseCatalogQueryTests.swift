import Foundation
import XCTest
@testable import ForumCore

final class BookhouseCatalogQueryTests: XCTestCase {
  private func entry(_ id: String, name: String = "SevenLetters Novel", range: String, author: String = "Writer") -> ForumEntry {
    ForumEntry(title: "\u{3010}\(name)\u{3011}(\(range)) \u{4F5C}\u{8005}:\(author)",
      url: BookhouseSitePolicy.thread(id)!, authorID: id, authorName: "Uploader \(id)")
  }
  private func page(_ entry: ForumEntry) -> ForumPage {
    ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: entry.id, author: entry.authorName ?? "", date: "", number: "", blocks: [], authorID: entry.authorID)], pageNumber: 1)
  }
  func testCatalogQueryUsesAtMostSevenCharactersWithoutChangingBookIdentity() throws {
    let name = "\u{4E00}\u{4E8C}\u{4E09}\u{56DB}\u{4E94}\u{516D}\u{4E03}\u{516B}\u{4E5D}"
    let book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", name: name + " (Alternate name)", range: "1")))
    XCTAssertEqual(book.catalogKeywords, String(name.prefix(7)))
    XCTAssertEqual(book.searchTitle, name)
    XCTAssertEqual(book.title, name + " (Alternate name)")
    let url = try XCTUnwrap(BookhouseSitePolicy.search(book.catalogKeywords))
    XCTAssertEqual(BookhouseSitePolicy.route(url)?.parameters["keywords"], String(name.prefix(7)))
    let short = try XCTUnwrap(BookhouseFollowedBook(entry: entry("2", name: "Short", range: "1")))
    XCTAssertEqual(short.catalogKeywords, "Short")
  }
  func testSearchCatalogMatchesLiteraryAuthorAcrossTitleVariantsAndUploaders() throws {
    let seed = entry("1", range: "\u{756A}\u{5916}7-8")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: seed))
    let regular = entry("2", name: "SevenLetters Novel (Alternate name)", range: "1-235")
    let extra = entry("3", name: "SevenLetters Novel Extras", range: "\u{756A}\u{5916}1-6")
    let wrong = entry("4", range: "236", author: "Other writer")
    let undeclared = ForumEntry(title: "\u{3010}SevenLetters Novel\u{3011}(237)", url: BookhouseSitePolicy.thread("5")!, authorName: "Writer")
    let unnumbered = ForumEntry(title: "SevenLetters Novel discussion \u{4F5C}\u{8005}:Writer", url: BookhouseSitePolicy.thread("6")!)
    XCTAssertFalse(book.matches(extra)) // Ordinary follow matching is still book-specific.
    var library = LibraryDocument(site: .bookhouse)
    library.followedBooks[book.id] = book
    XCTAssertEqual(library.followedBook(for: extra)?.id, book.id)
    XCTAssertEqual(library.followedBook(for: regular)?.id, book.id)
    XCTAssertNil(library.followedBook(for: wrong))
    XCTAssertTrue(book.matchesCatalogResult(extra))
    XCTAssertFalse(book.matchesCatalogResult(wrong))
    XCTAssertFalse(book.matchesCatalogResult(undeclared))
    XCTAssertFalse(book.matchesCatalogResult(unnumbered))
    book.record(url: seed.url, chapter: BookhouseChapterTitle.extraOffset + 7, paragraph: 12)
    let position = book.position, snapshot = book
    book.mergeCatalog([regular, extra, wrong, undeclared, unnumbered, regular], verifiedBy: snapshot, checkedAt: Date())
    XCTAssertEqual(book.chapters.count, 3)
    XCTAssertEqual(book.latestRegularChapter, 235)
    XCTAssertEqual(book.latestExtraChapter, 8)
    XCTAssertEqual(book.position, position)
    XCTAssertTrue(book.accepts(page(regular)))
    XCTAssertTrue(book.accepts(page(extra)))
    XCTAssertFalse(book.accepts(page(entry("3", name: "Unrelated title", range: "\u{756A}\u{5916}1-6"))))
    XCTAssertFalse(book.accepts(page(entry("3", name: "SevenLetters Novel Extras", range: "\u{756A}\u{5916}1-6", author: "Other writer"))))
    XCTAssertEqual(book.adjacentChapter(to: book.chapter(containing: 235)!, boundary: 235, edge: .next)?.url, extra.url)
    let restored = try JSONDecoder().decode(BookhouseFollowedBook.self, from: JSONEncoder().encode(book))
    XCTAssertEqual(restored.chapters, book.chapters)
    XCTAssertTrue(restored.accepts(page(extra)))
  }
  func testVersionTwoCatalogRechecksOnceAndPreservesIdentityProgressAndChapters() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", range: "\u{756A}\u{5916}7-8")))
    book.catalogVersion = 2; book.checkedAt = Date(); book.attemptedAt = Date()
    book.record(url: book.seed, chapter: BookhouseChapterTitle.extraOffset + 7, paragraph: 9)
    let original = book
    var library = LibraryDocument(site: .bookhouse)
    library.followedBooks[book.id] = book
    library = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(library))
    let migrated = try XCTUnwrap(library.followedBooks[book.id])
    XCTAssertEqual(migrated.id, original.id)
    XCTAssertEqual(migrated.position, original.position)
    XCTAssertEqual(migrated.chapters, original.chapters)
    XCTAssertNil(migrated.checkedAt); XCTAssertNil(migrated.attemptedAt)
    var restored = try JSONDecoder().decode(BookhouseFollowedBook.self, from: JSONEncoder().encode(migrated))
    restored.checkedAt = Date()
    XCTAssertFalse(restored.migrateCatalog())
    XCTAssertNotNil(restored.checkedAt)
  }
  func testRefreshEligibilityIncludesBooksAndKeepsForumLibrariesSeparate() throws {
    for site in ForumSite.allCases { XCTAssertFalse(LibraryDocument(site: site).hasRefreshTargets) }
    var bookhouse = LibraryDocument(site: .bookhouse)
    let book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", range: "1")))
    bookhouse.followedBooks[book.id] = book
    XCTAssertTrue(bookhouse.hasRefreshTargets)
    XCTAssertFalse(bookhouse.site.supportsThreadUpdates)
    var south = LibraryDocument(site: .south)
    south.followAuthor(id: "123", name: "Writer")
    XCTAssertTrue(south.hasRefreshTargets)
    var simp = LibraryDocument(site: .simp)
    simp.bookmarks = [SavedPage(url: URL(string: "https://simpcity.cr/threads/example.123/")!, title: "Example")]
    XCTAssertTrue(simp.hasRefreshTargets)
  }
}
