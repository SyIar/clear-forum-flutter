import Foundation
import XCTest
@testable import ForumCore

final class BookmarkTitleTests: XCTestCase {
  func testCustomTitlesSurviveMetadataRefreshAndPersistenceForBothForums() throws {
    for address in ["https://simpcity.cr/threads/example.42/page-3#post-9", "https://south-plus.net/read.php?tid-42-page-3.html#post_9"] {
      let customURL = try XCTUnwrap(URL(string: address))
      let automaticURL = try XCTUnwrap(SitePolicy.threadRoot(customURL))
      var library = LibraryDocument(site: try XCTUnwrap(ForumSite(url: customURL)))
      library.toggle(SavedPage(url: customURL, title: "My saved label", titleIsCustom: true))
      library.toggle(SavedPage(url: automaticURL, title: automaticURL.path))
      library.remember(SavedPage(url: customURL, title: "Old site title"))
      library = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(library))
      let page = ForumPage(url: automaticURL, title: "Current site title", kind: .posts, entries: [], posts: [], pageNumber: 1)
      library.capturePresentation(page)
      XCTAssertEqual(library.bookmarks.map(\.title), ["My saved label", "Current site title"])
      XCTAssertEqual(library.bookmarks.map(\.titleIsCustom), [true, false])
      XCTAssertEqual(library.bookmarks.map(\.url), [customURL, automaticURL])
      XCTAssertEqual(library.recent.first?.title, "Current site title")
      XCTAssertEqual(library.recent.first?.url, customURL)
      let directory = ForumPage(url: library.site.start, title: "Forum", kind: .threads,
                                entries: [ForumEntry(title: "Renamed site title", url: automaticURL)], posts: [], pageNumber: 1)
      library.capturePresentation(directory)
      XCTAssertEqual(library.bookmarks.map(\.title), ["My saved label", "Renamed site title"])
    }
  }

  func testLegacyBookmarkNamesArePreservedWhilePathPlaceholdersResolve() throws {
    let source = #"{"version":1,"bookmarks":[{"url":"https://simpcity.cr/threads/example.42/page-3#post-9","title":"Existing label"},{"url":"https://simpcity.cr/threads/example.42/","title":"/threads/example.42/"}],"recent":[]}"#
    var library = try JSONDecoder().decode(LibraryDocument.self, from: Data(source.utf8))
    let destinations = library.bookmarks.map(\.url)
    library.synchronizeTitle("Fetched title", for: try XCTUnwrap(destinations.last))
    XCTAssertEqual(library.bookmarks.map(\.title), ["Existing label", "Fetched title"])
    XCTAssertEqual(library.bookmarks.map(\.titleIsCustom), [true, false])
    let restored = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(library))
    XCTAssertEqual(restored.bookmarks, library.bookmarks)
    XCTAssertEqual(restored.bookmarks.map(\.url), destinations)
  }

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
