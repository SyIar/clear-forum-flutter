import Foundation
import XCTest
@testable import ForumCore

final class BookhouseLibraryPersistenceTests: XCTestCase {
  private let extra = BookhouseChapterTitle.extraOffset
  private func entry(_ id: String, _ range: String) -> ForumEntry {
    ForumEntry(title: "\u{3010}Novel (Alternate title)\u{3011}(\(range)) \u{4F5C}\u{8005}:Writer",
      url: BookhouseSitePolicy.thread(id)!, authorName: "Uploader \(id)")
  }

  func testRegularAndExtraSeedsSurviveRepeatedLibrarySaveAndLoadWithProgress() throws {
    let suite = "BookhouseLibraryPersistenceTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let regular = entry("1", "1-235"), side = entry("2", "\u{756A}\u{5916}7-8")
    for seed in [regular, side] {
      var book = try XCTUnwrap(BookhouseFollowedBook(entry: seed))
      book.merge([regular, side], checkedAt: Date(timeIntervalSince1970: 1_700_000_000))
      book.record(url: regular.url, chapter: 42, paragraph: 17)
      book.record(url: side.url, chapter: extra + 7, paragraph: 3)
      var library = LibraryDocument(site: .bookhouse)
      library.followedBooks[book.id] = book
      for _ in 0..<3 {
        try library.save(to: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        library = try LibraryDocument.load(from: reopened, site: .bookhouse)
        XCTAssertEqual(library.followedBooks[book.id], book)
        XCTAssertEqual(library.readingBooks.count, 1)
        XCTAssertEqual(library.followedBooks[book.id]?.resumeURL, side.url)
        XCTAssertEqual(library.followedBooks[book.id]?.maximumReadRegular, 42)
      }
    }
  }

  func testAddingExtrasDuringCatalogRefreshKeepsAnExistingRegularBookOnReload() throws {
    let suite = "BookhouseLibraryPersistenceTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let regular = entry("1", "1-235")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: regular))
    book.record(url: regular.url, chapter: 200, paragraph: 9)
    var library = LibraryDocument(site: .bookhouse)
    library.followedBooks[book.id] = book
    try library.save(to: defaults)
    library = try LibraryDocument.load(from: defaults, site: .bookhouse)
    XCTAssertEqual(library.followedBooks[book.id], book)

    let refreshedAt = Date(timeIntervalSince1970: 1_700_000_000)
    library.followedBooks[book.id]?.mergeCatalog([entry("2", "\u{756A}\u{5916}1-8")], verifiedBy: book, checkedAt: refreshedAt)
    // A later unsuccessful check only advances attemptedAt and must not erase
    // the existing mixed catalog on the next launch.
    library.followedBooks[book.id]?.attemptedAt = refreshedAt.addingTimeInterval(3_600)
    let expected = try XCTUnwrap(library.followedBooks[book.id])
    try library.save(to: defaults)
    library = try LibraryDocument.load(from: defaults, site: .bookhouse)
    XCTAssertEqual(library.followedBooks[book.id], expected)
    XCTAssertEqual(library.followedBooks[book.id]?.position, book.position)
    XCTAssertEqual(library.followedBooks[book.id]?.latestExtraChapter, 8)
  }

  func testLegacyExtraCatalogMigrationKeepsIdentityAndPositionThroughLibraryLoad() throws {
    let suite = "BookhouseLibraryPersistenceTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", "\u{756A}\u{5916}7-8")))
    book.merge([entry("2", "1-235")], checkedAt: Date(timeIntervalSince1970: 1_700_000_000))
    book.record(url: book.seed, chapter: extra + 8, paragraph: 12)
    book.catalogVersion = 2; book.authorSource = nil; book.author = "Uploader 1"; book.authorID = "1"
    var library = LibraryDocument(site: .bookhouse)
    library.followedBooks[book.id] = book
    try library.save(to: defaults)
    library = try LibraryDocument.load(from: defaults, site: .bookhouse)
    let restored = try XCTUnwrap(library.followedBooks[book.id])
    XCTAssertEqual(restored.id, book.id); XCTAssertEqual(restored.followedAt, book.followedAt)
    XCTAssertEqual(restored.position, book.position); XCTAssertEqual(restored.chapters, book.chapters)
    XCTAssertEqual(restored.author, "Writer"); XCTAssertEqual(restored.authorSource, .title)
    XCTAssertNil(restored.authorID); XCTAssertNil(restored.checkedAt)
    try library.save(to: defaults)
    XCTAssertEqual(try LibraryDocument.load(from: defaults, site: .bookhouse).followedBooks[book.id], restored)
  }

  func testRangeValidationAcceptsBothSectionBoundsAndRejectsInvalidCatalogs() throws {
    let suite = "BookhouseLibraryPersistenceTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let regular = entry("1", "1-100000"), side = entry("2", "\u{756A}\u{5916}1-100000")
    var valid = try XCTUnwrap(BookhouseFollowedBook(entry: regular))
    valid.merge([side], checkedAt: Date(timeIntervalSince1970: 1_700_000_000))
    var library = LibraryDocument(site: .bookhouse)
    library.followedBooks[valid.id] = valid
    for (first, last) in [(0, 1), (2, 1), (extra + 2, extra + 1),
                          (extra, extra + 1), (extra + 1, extra * 2 + 1), (Int.min, 1), (1, Int.max)] {
      var invalid = try XCTUnwrap(BookhouseFollowedBook(entry: regular))
      invalid.chapters = [BookhouseChapter(url: regular.url, title: regular.title, first: first, last: last)]
      library.followedBooks[invalid.id] = invalid
    }
    var foreign = try XCTUnwrap(BookhouseFollowedBook(entry: side))
    foreign.chapters = [BookhouseChapter(url: URL(string: "https://example.com/chapter")!, title: side.title, first: extra + 1, last: extra + 8)]
    library.followedBooks[foreign.id] = foreign
    try library.save(to: defaults)
    let restored = try LibraryDocument.load(from: defaults, site: .bookhouse)
    XCTAssertEqual(restored.followedBooks, [valid.id: valid])
  }
}
