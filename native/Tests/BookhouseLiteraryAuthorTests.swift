import Foundation
import XCTest
@testable import ForumCore

final class BookhouseLiteraryAuthorTests: XCTestCase {
  private func entry(_ id: String, chapter: String, writer: String = "Novel Writer", uploader: String? = "Uploader A", book: String = "Novel", title: String? = nil) -> ForumEntry {
    ForumEntry(title: title ?? "\u{3010}\(book)\u{3011}(\(chapter)) \u{4F5C}\u{8005}:\(writer)",
      url: BookhouseSitePolicy.thread(id)!, authorID: id, authorName: uploader)
  }
  private func page(_ entry: ForumEntry) -> ForumPage {
    ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: entry.id, author: entry.authorName ?? "", date: "", number: "",
        blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Example passage")])], authorID: entry.authorID)], pageNumber: 1)
  }
  func testExplicitAuthorMatchesAcrossUploadersButRejectsOtherBooksAndWriters() throws {
    let seed = entry("100", chapter: "27")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: seed))
    XCTAssertEqual(book.author, "Novel Writer")
    XCTAssertEqual(book.authorSource, .title)
    XCTAssertNil(book.authorID)
    let otherUploader = entry("200", chapter: "28", uploader: "Uploader B")
    XCTAssertTrue(book.matches(otherUploader))
    XCTAssertTrue(book.matches(entry("300", chapter: "29", uploader: nil)))
    let tagged = entry("350", chapter: "29", writer: "Novel Writer\u{300E}Category\u{300F}", uploader: "Uploader C")
    XCTAssertTrue(book.matches(tagged))
    XCTAssertFalse(book.matches(entry("400", chapter: "30", writer: "Other writer")))
    XCTAssertFalse(book.matches(entry("500", chapter: "30", book: "Novel sequel")))
    let undeclared = entry("600", chapter: "30", uploader: "Novel Writer", title: "\u{3010}Novel\u{3011}(30)")
    XCTAssertFalse(book.matches(undeclared))
    XCTAssertFalse(book.accepts(page(otherUploader)))
    book.merge([otherUploader], checkedAt: Date())
    XCTAssertTrue(book.accepts(page(otherUploader)))
    var wrong = page(otherUploader)
    wrong.title = entry("200", chapter: "28", writer: "Other writer").title
    XCTAssertFalse(book.accepts(wrong))
  }

  func testSplitChaptersAndCrossUploaderBundlesCompleteTheCatalog() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("100", chapter: "37")))
    let numbers = Array(6...37).filter { ![26, 34].contains($0) }.map(String.init)
    let tokens = ["1-28", "5-9"] + numbers + ["26\u{4E0B}", "26\u{4E0A}", "34 \u{4E0B}", "34 \u{4E0A}"]
    let entries = tokens.enumerated().map { entry(String($0.offset + 1), chapter: $0.element, uploader: "Uploader \($0.offset % 4)") }
    book.merge(entries, checkedAt: Date())
    for number in 1...37 { XCTAssertNotNil(book.chapter(containing: number), "Missing chapter \(number)") }
    XCTAssertEqual(book.latestChapter, 37)
    XCTAssertEqual(book.chapters.filter { $0.first == 26 }.compactMap(\.part), [.upper, .lower])
    XCTAssertEqual(book.chapters.filter { $0.first == 34 }.compactMap(\.part), [.upper, .lower])
    XCTAssertEqual(book.chapter(containing: 26)?.part, .upper)
    XCTAssertEqual(book.chapter(containing: 26, preferLastPart: true)?.part, .lower)
    let restored = try JSONDecoder().decode(BookhouseFollowedBook.self, from: JSONEncoder().encode(book))
    XCTAssertEqual(restored.chapters, book.chapters)
    XCTAssertEqual(restored.chapter(containing: 26)?.part, .upper)
    XCTAssertEqual(BookhouseChapterTitle("\u{3010}Novel\u{3011}\u{7B2C}26\u{7AE0}\u{FF08}\u{4E0B}\u{FF09}")?.part, .lower)
    XCTAssertNil(BookhouseChapterTitle("\u{3010}Novel\u{3011}(1-3\u{4E0A})"))
  }

  func testReadingWindowJoinsBothPartsBeforeAdvancingInEitherDirection() throws {
    let entries = [entry("1", chapter: "25"), entry("2", chapter: "26\u{4E0A}", uploader: "Uploader B"),
      entry("3", chapter: "26\u{4E0B}", uploader: "Uploader C"), entry("4", chapter: "27", uploader: "Uploader D")]
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entries[0]))
    book.merge(entries, checkedAt: Date())
    var window = BookhouseReadingWindow()
    XCTAssertTrue(window.reset(page(entries[0]), book: book))
    for entry in entries.dropFirst() {
      XCTAssertEqual(window.target(.next, book: book)?.url, entry.url)
      XCTAssertTrue(window.insert(page(entry), at: .next, book: book))
    }
    XCTAssertEqual(window.paragraphs.map(\.chapter), [25, 26, 26, 27])
    XCTAssertEqual(Set(window.paragraphs.map(\.id)).count, 4)
    XCTAssertTrue(window.reset(page(entries[3]), book: book))
    for entry in entries.dropLast().reversed() {
      XCTAssertEqual(window.target(.previous, book: book)?.url, entry.url)
      XCTAssertTrue(window.insert(page(entry), at: .previous, book: book))
    }
    XCTAssertEqual(window.paragraphs.map(\.chapter), [25, 26, 26, 27])
    let lower = window.paragraphs[2]
    book.record(url: lower.url, chapter: lower.chapter, paragraph: lower.index)
    XCTAssertEqual(book.position?.url, entries[2].url)
  }

  func testLegacyLibraryMigratesIdentityAndInvalidatesOnlyTheIncompleteCatalog() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", chapter: "27")))
    book.record(url: book.seed, chapter: 27, paragraph: 12)
    book.checkedAt = Date(); book.attemptedAt = Date()
    let wrong = entry("999", chapter: "10", writer: "Other writer")
    book.chapters.append(BookhouseChapter(url: wrong.url, title: wrong.title, first: 10, last: 10))
    var library = LibraryDocument(site: .bookhouse); library.followedBooks[book.id] = book
    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
    var books = try XCTUnwrap(raw["followedBooks"] as? [String: [String: Any]])
    books[book.id]?.removeValue(forKey: "authorSource")
    books[book.id]?["author"] = "Uploader A"; books[book.id]?["authorID"] = "OldAccountID"
    raw["followedBooks"] = books
    let restored = try JSONDecoder().decode(LibraryDocument.self, from: JSONSerialization.data(withJSONObject: raw))
    var migrated = try XCTUnwrap(restored.followedBooks[book.id])
    XCTAssertEqual(migrated.author, "Novel Writer")
    XCTAssertEqual(migrated.authorSource, .title)
    XCTAssertNil(migrated.authorID)
    XCTAssertNil(migrated.checkedAt); XCTAssertNil(migrated.attemptedAt)
    XCTAssertEqual(migrated.id, book.id); XCTAssertEqual(migrated.seed, book.seed)
    XCTAssertEqual(migrated.position, book.position); XCTAssertEqual(migrated.maximumRead, book.maximumRead)
    XCTAssertEqual(migrated.chapters.map(\.url), [book.seed])
    let position = migrated.position
    migrated.merge([entry("2", chapter: "28", uploader: "Uploader B")], checkedAt: Date())
    XCTAssertEqual(migrated.position, position)
    let encoded = try JSONEncoder().encode(migrated)
    var again = try JSONDecoder().decode(BookhouseFollowedBook.self, from: encoded)
    XCTAssertFalse(again.migrateAuthor())
    XCTAssertEqual(again.checkedAt, migrated.checkedAt)
    XCTAssertTrue(again.matches(entry("3", chapter: "29", uploader: "Uploader C")))
  }

  func testLegacyBookWithoutDeclaredAuthorKeepsAccountAndRefreshDates() throws {
    let source = entry("1", chapter: "27", title: "\u{3010}Novel\u{3011}(27)")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: source))
    book.authorSource = nil; book.checkedAt = Date(); book.attemptedAt = Date()
    book.record(url: book.seed, chapter: 27, paragraph: 7)
    let old = book
    XCTAssertTrue(book.migrateAuthor())
    XCTAssertEqual(book.author, "Uploader A")
    XCTAssertEqual(book.authorSource, .postingAccount)
    XCTAssertEqual(book.authorID, old.authorID)
    XCTAssertEqual(book.checkedAt, old.checkedAt); XCTAssertEqual(book.attemptedAt, old.attemptedAt)
    XCTAssertEqual(book.position, old.position)
  }

  func testRefreshCanPromoteAuthorWhileKeepingNewerReadingPosition() throws {
    let seed = entry("1", chapter: "27", title: "\u{3010}Novel\u{3011}(27)")
    var current = try XCTUnwrap(BookhouseFollowedBook(entry: seed))
    var snapshot = current
    XCTAssertEqual(snapshot.authorSource, .postingAccount)
    XCTAssertTrue(snapshot.verifySeed(page(entry("1", chapter: "27"))))
    XCTAssertEqual(snapshot.authorSource, .title)
    XCTAssertEqual(snapshot.chapters.first?.url, current.seed)
    current.record(url: current.seed, chapter: 27, paragraph: 20)
    let position = current.position
    current.mergeCatalog([entry("2", chapter: "28", uploader: "Uploader B")], verifiedBy: snapshot, checkedAt: Date())
    XCTAssertEqual(current.author, "Novel Writer")
    XCTAssertEqual(current.position, position)
    XCTAssertEqual(current.chapters.count, 2)
    XCTAssertTrue(current.accepts(page(entry("1", chapter: "27"))))
  }
}
