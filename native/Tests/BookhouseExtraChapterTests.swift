import Foundation
import XCTest
@testable import ForumCore

final class BookhouseExtraChapterTests: XCTestCase {
  private let extra = BookhouseChapterTitle.extraOffset
  private func entry(_ id: String, _ range: String, name: String = "Novel (Alternate title)", author: String = "Writer") -> ForumEntry {
    ForumEntry(title: "\u{3010}\(name)\u{3011}\u{FF08}\(range)\u{FF09}\u{4F5C}\u{8005}\u{FF1A}\(author)",
      url: BookhouseSitePolicy.thread(id)!, authorName: "Uploader \(id)")
  }
  private func page(_ entry: ForumEntry, headings: [String] = ["Example passage"]) -> ForumPage {
    ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: entry.id, author: entry.authorName ?? "", date: "", number: "",
        blocks: headings.map { BodyBlock(kind: .paragraph, runs: [TextRun(text: $0)]) })], pageNumber: 1)
  }
  func testHighlightedExtraSearchResultCanStartFollowingAndUsesPrimarySearchTitle() throws {
    let source = """
    <ul class="thread-list"><li class="l-m1"><a href="index.php?app=forum&amp;act=threadview&amp;tid=14614705">\u{3010}<span class='keyword'>Novel</span>\u{FF08}Alternate title\u{FF09}\u{3011}\u{FF08}\u{756A}\u{5916} 7-8\u{FF09}\u{4F5C}\u{8005}\u{FF1A}Writer</a>- <font color="black">Uploader</font><i>09/04/26</i></li></ul>
    """
    let result = try BookhouseParser().parse(source, url: BookhouseSitePolicy.search("Novel")!)
    let book = try XCTUnwrap(result.entries.first.flatMap { BookhouseFollowedBook(entry: $0) })
    XCTAssertEqual(book.author, "Writer")
    XCTAssertEqual(book.searchTitle, "Novel")
    XCTAssertEqual(book.chapters[0].first, extra + 7)
    XCTAssertEqual(book.chapters[0].last, extra + 8)
    XCTAssertEqual(book.chapterNumber(at: 7), extra + 7)
    XCTAssertEqual(BookhouseSitePolicy.route(BookhouseSitePolicy.search(book.searchTitle)!)?.parameters["keywords"], "Novel")
  }
  func testRegularAndExtraCatalogsMergeAcrossUploadersWithoutMixingNumbersOrFanFiction() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", "\u{756A}\u{5916} 7-8")))
    let regular = entry("2", "1-235", name: "Novel")
    let extras = [entry("3", "\u{756A}\u{5916}1-4"), entry("4", "\u{756A}\u{5916}5-6")]
    let complete = entry("5", "189-192")
    let missingBracket = ForumEntry(title: String(complete.title.dropFirst()), url: complete.url, authorName: complete.authorName)
    book.merge([regular, missingBracket] + extras + [entry("6", "1", name: "Novel fan fiction"), entry("7", "236", author: "Other")], checkedAt: Date())
    XCTAssertEqual(book.chapters.count, 5)
    XCTAssertEqual(book.chapters.last?.first, extra + 7)
    XCTAssertEqual(book.latestRegularChapter, 235)
    XCTAssertEqual(book.latestExtraChapter, 8)
    XCTAssertEqual(book.sliderChapterCount, 243)
    XCTAssertEqual(book.sliderPosition(for: extra + 7), 242)
    XCTAssertEqual(book.chapterNumber(at: 236), extra + 1)
    XCTAssertEqual(book.chapter(containing: 7)?.url, regular.url)
    XCTAssertEqual(book.chapter(containing: extra + 7)?.url, book.seed)
    XCTAssertTrue(book.matches(missingBracket))
    XCTAssertTrue(book.matches(entry("8", "236", name: "Novel")))
    XCTAssertFalse(book.matches(entry("9", "236", name: "Novel sequel")))
    XCTAssertFalse(book.matches(entry("11", "236", name: "Novel (Sequel)")))
    XCTAssertFalse(book.matches(entry("10", "236", author: "Uploader 1")))
  }
  func testSeamlessReadingCrossesRegularExtraBoundaryBothWaysAndPrefetchesExtras() throws {
    let regular = entry("1", "234-235")
    let firstExtra = entry("2", "\u{756A}\u{5916}1-4")
    let secondExtra = entry("3", "\u{756A}\u{5916}5-6")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: regular))
    book.merge([firstExtra, secondExtra], checkedAt: Date())
    var window = BookhouseReadingWindow()
    let regularPage = page(regular, headings: ["\u{7B2C}234\u{7AE0} Start", "\u{7B2C}235\u{7AE0} End"])
    XCTAssertTrue(window.reset(regularPage, book: book))
    XCTAssertEqual(window.prefetchTarget(visibleIDs: [window.paragraphs.last!.id], book: book)?.url, firstExtra.url)
    XCTAssertTrue(window.insert(page(firstExtra), at: .next, book: book))
    XCTAssertTrue(window.insert(page(secondExtra), at: .next, book: book))
    XCTAssertEqual(window.paragraphs.map(\.chapter), [234, 235, extra + 1, extra + 5])
    book.record(url: firstExtra.url, chapter: extra + 3, paragraph: 0)
    XCTAssertEqual(book.offlineTargets.map(\.url), [firstExtra.url, secondExtra.url])
    XCTAssertTrue(window.reset(page(secondExtra), book: book))
    XCTAssertTrue(window.insert(page(firstExtra), at: .previous, book: book))
    XCTAssertTrue(window.insert(regularPage, at: .previous, book: book))
    XCTAssertEqual(window.paragraphs.map(\.chapter), [234, 235, extra + 1, extra + 5])
  }
  func testExtraHeadingsProgressAndRelaunchStaySeparateFromRegularChapters() throws {
    let source = entry("1", "\u{756A}\u{5916}7-8")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: source))
    let blocks = page(source, headings: ["\u{756A}\u{5916} 7 Heading", "Text", "\u{756A}\u{5916}\u{7B2C}8\u{7AE0} Heading", "End"]).posts[0].blocks
    let anchors = BookhouseChapterAnchors(blocks: blocks, chapter: book.chapters[0])
    XCTAssertEqual(anchors.paragraph(for: extra + 8), 2)
    XCTAssertNil(anchors.paragraph(for: 8))
    book.record(url: source.url, chapter: extra + 8, paragraph: 3)
    let restored = try JSONDecoder().decode(BookhouseFollowedBook.self, from: JSONEncoder().encode(book))
    XCTAssertEqual(restored.position?.chapter, extra + 8)
    XCTAssertEqual(restored.position?.paragraph, 3)
    XCTAssertEqual(restored.chapters, book.chapters)
  }
  func testNewRegularChaptersStillShowAnUpdateAfterReadingExtras() throws {
    let regular = entry("1", "1-235"), side = entry("2", "\u{756A}\u{5916}1-8")
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: regular))
    book.merge([side], checkedAt: Date())
    book.record(url: side.url, chapter: extra + 8, paragraph: 0)
    XCTAssertFalse(book.updated)
    let new = entry("3", "236")
    book.merge([new], checkedAt: Date())
    XCTAssertTrue(book.updated)
    book.record(url: new.url, chapter: 236, paragraph: 0)
    XCTAssertFalse(book.updated)
  }
  func testLegacySeedOnlyCatalogRechecksOnceWithoutLosingReadingPosition() throws {
    var book = try XCTUnwrap(BookhouseFollowedBook(entry: entry("1", "232-235")))
    book.checkedAt = Date(); book.attemptedAt = Date()
    book.record(url: book.seed, chapter: 234, paragraph: 8)
    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(book)) as? [String: Any])
    raw.removeValue(forKey: "catalogVersion")
    var legacy = try JSONDecoder().decode(BookhouseFollowedBook.self, from: JSONSerialization.data(withJSONObject: raw))
    XCTAssertTrue(legacy.migrateCatalog())
    XCTAssertNil(legacy.checkedAt); XCTAssertNil(legacy.attemptedAt)
    XCTAssertEqual(legacy.id, book.id); XCTAssertEqual(legacy.position, book.position)
    legacy.merge([entry("2", "1-231"), entry("3", "\u{756A}\u{5916}1-8")], checkedAt: Date())
    XCTAssertFalse(legacy.migrateCatalog())
    XCTAssertNotNil(legacy.checkedAt)
    XCTAssertEqual(legacy.chapters.count, 3)
    XCTAssertEqual(legacy.position, book.position)
  }
}
