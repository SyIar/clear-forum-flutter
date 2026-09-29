import Foundation
import XCTest
@testable import ForumCore

final class SouthAuthorBlockingTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private func page() -> ForumPage {
    ForumPage(url: url, title: "Sample", kind: .posts, entries: [], posts: [
      ForumPost(id: "post_tpc", author: "Same name", date: "", number: "#0", blocks: [BodyBlock(kind: .paragraph)], authorID: "101"),
      ForumPost(id: "post_12", author: "Same name", date: "", number: "#12", blocks: [BodyBlock(kind: .paragraph)], authorID: "102"),
      ForumPost(id: "post_100", author: "Same name", date: "", number: "#100", blocks: [BodyBlock(kind: .paragraph)])
    ], pageNumber: 1, loggedIn: true, maximumPostNumber: 100)
  }
  func testBlockingUsesUIDAndKeepsCacheAndFloorNumbersIntact() throws {
    var library = LibraryDocument(site: .south)
    let original = page()
    let cache = PageCache()
    cache.store(original)
    library.blockAuthor(id: "101", name: "Same name")
    let visible = library.visibleContent(in: try XCTUnwrap(cache.value(for: url)?.page))
    XCTAssertEqual(visible.posts.map(\.number), ["#12", "#100"])
    XCTAssertEqual(visible.maximumPostNumber, 100)
    XCTAssertEqual(cache.value(for: url)?.page.posts.count, 3)
    library.unblockAuthor("101")
    XCTAssertEqual(library.visibleContent(in: try XCTUnwrap(cache.value(for: url)?.page)).posts.count, 3)
    var simp = LibraryDocument(site: .simp)
    simp.blockAuthor(id: "101", name: "Same name")
    XCTAssertTrue(simp.blockedAuthors.isEmpty)
    XCTAssertEqual(simp.visibleContent(in: original).posts.count, 3)
  }
  func testTopicsBookmarksAndRecentReadingHideWithoutDeletingRecords() {
    var library = LibraryDocument(site: .south)
    let saved = SavedPage(url: url, title: "Sample")
    library.remember(saved)
    library.toggle(saved)
    library.capturePresentation(page())
    library.blockAuthor(id: "101", name: "Creator")
    XCTAssertTrue(library.hidesSavedPage(saved))
    XCTAssertEqual(library.bookmarks, [saved])
    XCTAssertEqual(library.recent, [saved])
    XCTAssertTrue(library.hidesSavedPage(SavedPage(url: SouthSitePolicy.authorTopics("101")!, title: "Topics")))
    var directory = page()
    directory.url = SouthSitePolicy.start; directory.kind = .threads; directory.posts = []
    directory.entries = [
      ForumEntry(title: "Known owner", url: url),
      ForumEntry(title: "Other creator", url: URL(string: "https://south-plus.net/read.php?tid-21.html")!, authorID: "102"),
      ForumEntry(title: "Blocked creator", url: URL(string: "https://south-plus.net/read.php?tid-22.html")!, authorID: "101")
    ]
    XCTAssertEqual(library.visibleContent(in: directory).entries.map(\.title), ["Other creator"])
    library.unblockAuthor("101")
    XCTAssertFalse(library.hidesSavedPage(saved))
    XCTAssertEqual(library.visibleContent(in: directory).entries.count, 3)
  }
  func testDirectoryAndHistoryCaptureThreadOwnerWithoutOverwritingItWithReplyAuthor() {
    var library = LibraryDocument(site: .south)
    var directory = page()
    directory.kind = .threads; directory.posts = []
    directory.entries = [ForumEntry(title: "Topic", url: url, authorID: "101")]
    library.capturePresentation(directory)
    var replies = page()
    replies.posts.removeFirst()
    library.capturePresentation(replies)
    XCTAssertEqual(library.presentations["20"]?.authorID, "101")
  }
  func testPersistenceAndMigrationAreIsolatedByForum() throws {
    let suite = "SouthAuthorBlockingTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var library = LibraryDocument(site: .south)
    library.remember(SavedPage(url: url, title: "Sample"))
    library.capturePresentation(page())
    library.blockAuthor(id: "101", name: "Creator")
    library.blockAuthor(id: "0", name: "Invalid")
    try library.save(to: defaults)
    let restored = try LibraryDocument.load(from: defaults, site: .south)
    XCTAssertEqual(restored.blockedAuthors, ["101": "Creator"])
    XCTAssertTrue(restored.hidesSavedPage(restored.recent[0]))
    XCTAssertTrue(try LibraryDocument.load(from: defaults, site: .simp).blockedAuthors.isEmpty)
    var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
    old.removeValue(forKey: "blockedAuthors")
    let data = try JSONSerialization.data(withJSONObject: old)
    defaults.set(String(decoding: data, as: UTF8.self), forKey: LibraryDocument.key(for: .south))
    let migrated = try LibraryDocument.load(from: defaults, site: .south)
    XCTAssertTrue(migrated.blockedAuthors.isEmpty)
    XCTAssertEqual(migrated.recent.count, 1)
  }
}
