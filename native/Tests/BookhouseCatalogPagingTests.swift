import Foundation
import XCTest
@testable import ForumCore

final class BookhouseCatalogPagingTests: XCTestCase {
  private func cursorPage(_ cursor: Int?, ids: [Int], next: Int?) -> ForumPage {
    ForumPage(url: cursor.flatMap { BookhouseSitePolicy.cursor(String($0)) } ?? BookhouseSitePolicy.start,
      title: "Library", kind: .threads,
      entries: ids.map { ForumEntry(title: "Novel \($0)", url: BookhouseSitePolicy.thread(String($0))!) },
      posts: [], next: next.flatMap { BookhouseSitePolicy.cursor(String($0)) }, pageNumber: 1)
  }
  func testCursorPagingDeduplicatesAndRecoversPreviousPagesAfterWindowEviction() {
    let first = cursorPage(nil, ids: [100, 99], next: 99)
    let second = cursorPage(99, ids: [99, 98], next: 98)
    let third = cursorPage(98, ids: [97, 96], next: 96)
    let fourth = cursorPage(96, ids: [95, 94], next: nil)
    var window = ReaderPageWindow(countLimit: 2)
    window.reset(first)
    XCTAssertNil(window.target(.previous))
    XCTAssertEqual(window.target(.next), second.url)
    XCTAssertTrue(window.insert(second, at: .next, keeping: first.url))
    XCTAssertEqual(window.combined(active: first).entries.map(\.title), ["Novel 100", "Novel 99", "Novel 98"])
    XCTAssertEqual(first.entries.count, 2)
    XCTAssertTrue(window.insert(third, at: .next, keeping: second.url))
    XCTAssertEqual(window.pages.map(\.url), [second.url, third.url])
    XCTAssertEqual(window.target(.previous), first.url)
    XCTAssertTrue(window.insert(fourth, at: .next, keeping: third.url))
    XCTAssertEqual(window.pages.map(\.url), [third.url, fourth.url])
    XCTAssertNil(window.target(.next))
    XCTAssertTrue(window.insert(second, at: .previous, keeping: third.url))
    XCTAssertEqual(window.target(.previous), first.url)
    XCTAssertEqual(window.page(containing: third.entries[0].id)?.url, third.url)
    window.reset(first)
    XCTAssertNil(window.target(.previous))
  }
  func testWrongCursorResponseAndNonAdvancingLinksDoNotReplaceCurrentRows() {
    let first = cursorPage(100, ids: [99, 98], next: 98)
    var window = ReaderPageWindow(); window.reset(first)
    XCTAssertFalse(window.insert(cursorPage(97, ids: [96], next: 96), at: .next, keeping: first.url))
    XCTAssertEqual(window.pages.map(\.url), [first.url])
    var looping = first; looping.next = BookhouseSitePolicy.cursor("101")
    window.reset(looping); XCTAssertNil(window.target(.next))
    looping.next = BookhouseSitePolicy.search("Different listing")
    window.reset(looping); XCTAssertNil(window.target(.next))
    looping.next = URL(string: "https://example.com/list")!
    window.reset(looping); XCTAssertNil(window.target(.next))
  }
  func testSearchPagesJoinInBothDirectionsAndPreserveQueryFilters() {
    let root = BookhouseSitePolicy.search("Novel")!
    func result(_ number: Int, root: URL) -> ForumPage {
      ForumPage(url: BookhouseSitePolicy.pageURL(root, number: number)!, title: "Results", kind: .threads,
        entries: [ForumEntry(title: "Chapter \(number)", url: BookhouseSitePolicy.thread(String(number))!)], posts: [],
        previous: number > 1 ? BookhouseSitePolicy.pageURL(root, number: number - 1) : nil,
        next: number < 3 ? BookhouseSitePolicy.pageURL(root, number: number + 1) : nil, pageNumber: number, totalPages: 3)
    }
    let middle = result(2, root: root)
    var window = ReaderPageWindow(); window.reset(middle)
    XCTAssertTrue(window.insert(result(1, root: root), at: .previous, keeping: middle.url))
    XCTAssertFalse(window.insert(result(3, root: BookhouseSitePolicy.search("Other")!), at: .next, keeping: middle.url))
    XCTAssertTrue(window.insert(result(3, root: root), at: .next, keeping: middle.url))
    XCTAssertEqual(window.combined(active: middle).entries.map(\.title), ["Chapter 1", "Chapter 2", "Chapter 3"])
    XCTAssertNil(window.target(.previous)); XCTAssertNil(window.target(.next))
    var terminal = result(3, root: root)
    terminal.entries = []; terminal.totalPages = 4; terminal.next = nil
    window.reset(terminal)
    XCTAssertNil(window.target(.next))
  }
}
