import Foundation
import XCTest
@testable import ForumCore

final class BookmarkTitleTests: XCTestCase {
  func testThreadTitleRefreshPreservesEverySavedPageAndFloor() {
    var library = LibraryDocument()
    let first = URL(string: "https://simpcity.cr/threads/old-slug.42/page-3#post-9")!
    let second = URL(string: "https://simpcity.cr/threads/old-slug.42/page-7#post-30")!
    library.toggle(SavedPage(url: first, title: first.path))
    library.toggle(SavedPage(url: second, title: second.path))
    library.synchronizeTitle("Real thread title", for: URL(string: "https://simpcity.cr/threads/new-slug.42/")!)
    XCTAssertEqual(library.bookmarks.map(\.title), ["Real thread title", "Real thread title"])
    XCTAssertEqual(library.bookmarks.map(\.url), [first, second])
    XCTAssertTrue(library.recent.isEmpty)
    XCTAssertTrue(library.threads.isEmpty)
  }
  func testForeignAndEmptyTitlesNeverOverwriteBookmarks() {
    var library = LibraryDocument()
    let url = URL(string: "https://simpcity.cr/threads/example.42/")!
    library.toggle(SavedPage(url: url, title: "Saved"))
    library.synchronizeTitle("Foreign", for: URL(string: "https://south-plus.net/read.php?tid=42")!)
    library.synchronizeTitle(" ", for: url)
    XCTAssertEqual(library.bookmarks.first?.title, "Saved")
  }
  func testDirectoryMetadataUpdatesTitleWithoutMarkingThreadRead() {
    var library = LibraryDocument()
    let url = URL(string: "https://simpcity.cr/threads/example.42/page-3")!
    library.toggle(SavedPage(url: url, title: "Old"))
    let entry = ForumEntry(title: "New title", url: URL(string: "https://simpcity.cr/threads/example.42/")!)
    let directory = ForumPage(url: URL(string: "https://simpcity.cr/forums/example.9/")!, title: "Forum", kind: .threads,
                              entries: [entry], posts: [], pageNumber: 1)
    library.capturePresentation(directory)
    XCTAssertEqual(library.bookmarks.first?.title, "New title")
    XCTAssertEqual(library.bookmarks.first?.url, url)
    XCTAssertTrue(library.recent.isEmpty)
    XCTAssertTrue(library.threads.isEmpty)
  }
}
