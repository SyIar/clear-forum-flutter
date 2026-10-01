import Foundation
import XCTest
@testable import ForumCore

final class BookhouseReadingWindowTests: XCTestCase {
  private func entry(_ first: Int, _ last: Int) -> ForumEntry {
    ForumEntry(title: "\u{3010}Novel\u{3011}\u{7B2C}\(first)-\(last)\u{7AE0}",
      url: BookhouseSitePolicy.thread(String(first * 1000 + last))!, authorName: "Writer")
  }
  private func page(_ first: Int, _ last: Int, headings: Bool = true) -> ForumPage {
    let entry = entry(first, last)
    let blocks = (first...last).flatMap { number in
      [BodyBlock(kind: .paragraph, runs: [TextRun(text: headings ? "\u{7B2C}\(number)\u{7AE0} Heading" : "Heading")]),
       BodyBlock(kind: .paragraph, runs: [TextRun(text: "Body \(number)")])]
    }
    return ForumPage(url: entry.url, title: entry.title, kind: .posts, entries: [],
      posts: [ForumPost(id: "post", author: "Writer", date: "", number: "", blocks: blocks)], pageNumber: 1)
  }
  private func book(_ ranges: [(Int, Int)]) -> BookhouseFollowedBook {
    var book = BookhouseFollowedBook(entry: entry(ranges[0].0, ranges[0].1))!
    book.merge(ranges.map { entry($0.0, $0.1) }, checkedAt: Date())
    return book
  }
  func testBothEdgesJoinAndPreserveOriginalParagraphIdentityAndProgress() throws {
    let book = book([(1, 2), (3, 4), (5, 6)])
    let initial = page(3, 4)
    var window = BookhouseReadingWindow()
    XCTAssertTrue(window.reset(initial, book: book))
    let paragraph = window.paragraphs[2]
    XCTAssertTrue(window.insert(page(1, 2), at: .previous, book: book))
    XCTAssertTrue(window.insert(page(5, 6), at: .next, book: book))
    XCTAssertEqual(window.paragraphs.map(\.chapter), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6])
    let preserved = try XCTUnwrap(window.paragraph(id: paragraph.id))
    XCTAssertEqual(preserved.block.id, paragraph.block.id)
    XCTAssertEqual(preserved.index, 2)
    XCTAssertEqual(window.page(containing: paragraph.id)?.url, initial.url)
    XCTAssertEqual(preserved.chapter, 4)
    XCTAssertNil(window.target(.previous, book: book))
    XCTAssertNil(window.target(.next, book: book))
  }
  func testForwardAndReverseOverlapNeverRepeatBundledChapters() {
    let book = book([(1, 4), (3, 6), (7, 8)])
    var forward = BookhouseReadingWindow()
    forward.reset(page(1, 4), book: book)
    XCTAssertTrue(forward.insert(page(3, 6), at: .next, book: book))
    XCTAssertEqual(forward.slices.last?.range, 4..<8)
    XCTAssertEqual(forward.paragraphs.map(\.chapter), (1...6).flatMap { [$0, $0] })
    var backward = BookhouseReadingWindow()
    backward.reset(page(3, 6), book: book)
    XCTAssertTrue(backward.insert(page(1, 4), at: .previous, book: book))
    XCTAssertEqual(backward.slices.first?.range, 0..<4)
    XCTAssertEqual(backward.paragraphs.map(\.chapter), (1...6).flatMap { [$0, $0] })
  }
  func testUnrecognizedOverlapFailsWithoutChangingVisibleContent() {
    let book = book([(1, 4), (3, 6)])
    var window = BookhouseReadingWindow()
    window.reset(page(1, 4), book: book)
    let ids = window.paragraphs.map(\.id)
    XCTAssertFalse(window.insert(page(3, 6, headings: false), at: .next, book: book))
    XCTAssertEqual(window.paragraphs.map(\.id), ids)
    window.reset(page(3, 6), book: book)
    XCTAssertFalse(window.insert(page(1, 4, headings: false), at: .previous, book: book))
  }
  func testMissingChapterWrongAuthorAndMisdirectedResponsesCannotJoin() {
    let book = book([(1, 2), (3, 4), (7, 8)])
    var window = BookhouseReadingWindow()
    window.reset(page(1, 2), book: book)
    var wrong = page(3, 4); wrong.posts[0].author = "Other writer"
    XCTAssertFalse(window.insert(wrong, at: .next, book: book))
    XCTAssertFalse(window.insert(page(7, 8), at: .next, book: book))
    XCTAssertTrue(window.insert(page(3, 4), at: .next, book: book))
    XCTAssertFalse(window.insert(page(3, 4), at: .next, book: book))
    XCTAssertNil(window.target(.next, book: book))
  }
  func testHeadingsDetermineContinuationInsteadOfOverstatedTitleRange() {
    var book = book([(1, 4), (3, 4)])
    var first = page(1, 4)
    first.posts[0].blocks = Array(first.posts[0].blocks.prefix(4))
    var window = BookhouseReadingWindow()
    window.reset(first, book: book)
    XCTAssertEqual(window.target(.next, book: book)?.url, page(3, 4).url)
    XCTAssertTrue(window.insert(page(3, 4), at: .next, book: book))
    let visible = window.paragraphs[1]
    book.record(url: visible.url, chapter: visible.chapter, paragraph: visible.index)
    XCTAssertEqual(book.maximumRead, 1)
    XCTAssertEqual(book.position?.paragraph, 1)
  }
  func testTrimmingKeepsVisibleParagraphAndPermitsRevisitingEvictedChapter() {
    let book = book([(1, 2), (3, 4), (5, 6), (7, 8)])
    var window = BookhouseReadingWindow(countLimit: 2)
    window.reset(page(1, 2), book: book)
    window.insert(page(3, 4), at: .next, book: book)
    let visible = window.paragraphs.last!
    window.insert(page(5, 6), at: .next, book: book)
    window.trim(keeping: visible.id, preserving: .next)
    XCTAssertEqual(window.slices.map(\.first), [3, 5])
    XCTAssertNotNil(window.paragraph(id: visible.id))
    XCTAssertTrue(window.insert(page(1, 2), at: .previous, book: book))
    window.trim(keeping: visible.id, preserving: .previous)
    XCTAssertEqual(window.slices.map(\.first), [1, 3])
    XCTAssertNotNil(window.paragraph(id: visible.id))
  }
  func testCostEvictionAndChapterJumpResetKeepOnlyNeededPublications() {
    let book = book([(1, 2), (3, 4), (5, 6)])
    var window = BookhouseReadingWindow(costLimit: 1)
    window.reset(page(1, 2), book: book)
    window.insert(page(3, 4), at: .next, book: book)
    let visible = window.paragraphs.last!.id
    window.insert(page(5, 6), at: .next, book: book)
    window.trim(keeping: visible, preserving: .next)
    XCTAssertEqual(window.slices.count, 2)
    XCTAssertTrue(window.reset(page(1, 2), book: book))
    XCTAssertEqual(window.slices.count, 1)
    XCTAssertNil(window.paragraph(id: visible))
  }
}
