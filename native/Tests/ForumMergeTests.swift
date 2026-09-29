import Foundation
import XCTest
@testable import ForumCore

final class ForumMergeTests: XCTestCase {
  private let simp = URL(string: "https://simpcity.cr/threads/example.42/page-2")!
  private let south = URL(string: "https://south-plus.net/read.php?tid-42-page-2.html")!

  func testSameThreadNumberKeepsIndependentLibraries() throws {
    let name = "ForumMergeTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    var first = LibraryDocument(site: .simp)
    var second = LibraryDocument(site: .south)
    first.remember(SavedPage(url: simp, title: "First forum"))
    second.remember(SavedPage(url: south, title: "Second forum"))
    first.toggle(SavedPage(url: simp, title: "First bookmark"))
    second.toggle(SavedPage(url: south, title: "Second bookmark"))
    first.threads["42"] = ThreadReadState(seenMaximum: 100, latestMaximum: 108)
    second.threads["42"] = ThreadReadState(seenMaximum: 3, latestMaximum: 3)
    try first.save(to: defaults)
    try second.save(to: defaults)
    let restoredFirst = try LibraryDocument.load(from: defaults, site: .simp)
    let restoredSecond = try LibraryDocument.load(from: defaults, site: .south)
    XCTAssertEqual(restoredFirst.recent.first?.url, simp)
    XCTAssertEqual(restoredSecond.recent.first?.url, south)
    XCTAssertEqual(restoredFirst.bookmarks.first?.title, "First bookmark")
    XCTAssertEqual(restoredSecond.bookmarks.first?.title, "Second bookmark")
    XCTAssertEqual(restoredFirst.threads["42"]?.updated, true)
    XCTAssertEqual(restoredSecond.threads["42"]?.seenMaximum, 3)
    XCTAssertEqual(restoredSecond.threads["42"]?.updated, false)
  }

  func testLegacySimpLibraryAndFlutterFallbackSurviveUpgrade() throws {
    let name = "ForumMergeTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let legacy = #"{"version":1,"bookmarks":[{"url":"https://simpcity.cr/threads/example.42/page-2","title":"Saved"}],"recent":[],"threads":{"42":{"seenMaximum":100,"latestMaximum":108}},"presentations":{"42":{"thumbnail":"https://images.example/cover.jpg","tags":[{"title":"News","url":"https://simpcity.cr/forums/example.12/?prefix_id=1"}]}}}"#
    defaults.set(legacy, forKey: "flutter." + LibraryDocument.key)
    var restored = try LibraryDocument.load(from: defaults)
    XCTAssertEqual(restored.site, .simp)
    XCTAssertEqual(restored.bookmarks.first?.url, simp)
    XCTAssertEqual(restored.presentations["42"]?.tags.first?.title, "News")
    XCTAssertEqual(restored.threads["42"]?.updated, true)
    restored.remember(SavedPage(url: simp, title: "Visited"))
    try restored.save(to: defaults)
    XCTAssertNotNil(defaults.string(forKey: LibraryDocument.key))
    XCTAssertEqual(try LibraryDocument.load(from: defaults).recent.count, 1)
    XCTAssertTrue(try LibraryDocument.load(from: defaults, site: .south).bookmarks.isEmpty)
  }

  func testForeignLinksNeverEnterAnotherForumsLibraryOrTags() {
    var library = LibraryDocument(site: .simp)
    library.remember(SavedPage(url: south, title: "Foreign"))
    library.toggle(SavedPage(url: south, title: "Foreign"))
    library.mergePresentation(ThreadPresentation(thumbnail: URL(string: "https://images.example/foreign.jpg")), for: south)
    XCTAssertTrue(library.recent.isEmpty)
    XCTAssertTrue(library.bookmarks.isEmpty)
    XCTAssertTrue(library.presentations.isEmpty)
    library.mergePresentation(ThreadPresentation(tags: [ForumTag(title: "Foreign", url: south)]), for: simp)
    XCTAssertTrue(library.presentations.isEmpty)
    XCTAssertNil(SitePolicy.resolve(south.absoluteString, from: simp, internalOnly: true))
    XCTAssertNil(SitePolicy.resolve(simp.absoluteString, from: south, internalOnly: true))
  }

  func testCookieAndRouteOwnershipRejectsOtherForumAndLookalikes() throws {
    let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "fixture", .domain: ".simpcity.cr", .path: "/", .secure: "TRUE"]))
    XCTAssertTrue(ForumSite.simp.matches(cookie, url: simp))
    XCTAssertFalse(ForumSite.simp.matches(cookie, url: south))
    XCTAssertFalse(ForumSite.south.matches(cookie, url: south))
    XCTAssertFalse(ForumSite.simp.accepts(south))
    XCTAssertFalse(ForumSite.south.accepts(simp))
    for address in ["https://simpcity.cr.attacker.example/", "https://south-plus.net.attacker.example/", "https://user:pass@south-plus.net/", "https://south-plus.net:8443/"] {
      XCTAssertNil(ForumSite(url: URL(string: address)!))
    }
  }

  func testCacheIdentityIncludesForumAndNormalizesSouthAliases() {
    XCTAssertNotEqual(SitePolicy.pageCacheKey(simp), SitePolicy.pageCacheKey(south))
    XCTAssertNotEqual(LibraryDocument.recentKey(simp), LibraryDocument.recentKey(south))
    XCTAssertEqual(SitePolicy.pageCacheKey(south), SitePolicy.pageCacheKey(URL(string: "https://south-plus.net/read.php?tid=42&page=2")!))
    let cache = PageCache()
    let first = ForumPage(url: simp, title: "First", kind: .posts, entries: [], posts: [], pageNumber: 2, loggedIn: true)
    let second = ForumPage(url: south, title: "Second", kind: .posts, entries: [], posts: [], pageNumber: 2, loggedIn: nil)
    cache.store(first); cache.store(second)
    cache.savePosition("post-10", for: simp)
    cache.savePosition("post_20", for: south)
    XCTAssertEqual(cache.value(for: simp)?.visibleID, "post-10")
    XCTAssertEqual(cache.value(for: south)?.visibleID, "post_20")
  }

  func testWrongSiteDocumentFailsWithoutOverwritingExistingData() throws {
    let name = "ForumMergeTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try LibraryDocument(site: .south).save(to: defaults)
    let foreign = defaults.string(forKey: LibraryDocument.key(for: .south))
    defaults.set(foreign, forKey: LibraryDocument.key)
    XCTAssertThrowsError(try LibraryDocument.load(from: defaults, site: .simp))
    XCTAssertEqual(defaults.string(forKey: LibraryDocument.key), foreign)
  }

  func testZeroFloorCanBeUsedAsSouthReadBaseline() {
    var state = ThreadReadState()
    state.opened(maximum: 0)
    state.checked(maximum: 1)
    XCTAssertEqual(state.seenMaximum, 0)
    XCTAssertTrue(state.updated)
  }
}
