import Foundation
import XCTest
@testable import ForumCore

final class SouthReadingProgressTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/read.php?tid=20")!
  private func page(_ floors: [Int], url: URL? = nil) -> ForumPage {
    ForumPage(url: url ?? self.url, title: "Example thread", kind: .posts, entries: [],
              posts: floors.map { ForumPost(id: "post_\(9000 + $0)", author: "Example", date: "", number: "#\($0)", blocks: [], authorID: "100") },
              pageNumber: 1, loggedIn: true, maximumPostNumber: 100)
  }
  func testFetchedThreadMaximumNeverBecomesSouthViewedFloor() {
    var state = ThreadReadState()
    state.opened(maximum: 100)
    XCTAssertNil(state.displayedReadMaximum(for: .south))
    XCTAssertEqual(state.displayedReadMaximum(for: .simp), 100)
    XCTAssertTrue(state.viewed(maximum: 3))
    state.checked(maximum: 108)
    XCTAssertEqual(state.displayedReadMaximum(for: .south), 3)
    XCTAssertEqual(state.seenMaximum, 100)
    XCTAssertTrue(state.updated)
    state.opened(maximum: 108)
    XCTAssertEqual(state.viewedMaximum, 3)
    XCTAssertFalse(state.updated)
  }
  func testOnlyVisiblePostIDsAdvanceProgressNotLoadedOrUnknownRows() {
    var library = LibraryDocument(site: .south)
    let loaded = page(Array(0...100))
    XCTAssertFalse(library.recordVisiblePosts([], in: loaded))
    XCTAssertFalse(library.recordVisiblePosts(["top", "poll", "reader-next-page", "post_999999"], in: loaded))
    XCTAssertTrue(library.threads.isEmpty)
    XCTAssertTrue(library.recordVisiblePosts(["post_9002", "post_9003"], in: loaded))
    XCTAssertEqual(library.threads["20"]?.viewedMaximum, 3)
    XCTAssertNil(library.threads["20"]?.latestMaximum)
  }
  func testJoinedPagesAndAuthorFilteredRoutesShareMonotonicProgress() {
    var library = LibraryDocument(site: .south)
    var window = ReaderPageWindow()
    var first = page([0, 1, 2])
    first.totalPages = 2
    var second = page([3, 4, 5], url: URL(string: "https://south-plus.net/read.php?tid=20&page=2")!)
    second.pageNumber = 2
    window.reset(first)
    XCTAssertTrue(window.insert(second, at: .next, keeping: first.url))
    let joined = window.combined(active: first)
    XCTAssertTrue(library.recordVisiblePosts(["post_9004"], in: joined))
    XCTAssertFalse(library.recordVisiblePosts(["post_9001"], in: joined))
    let filtered = page([2, 8], url: URL(string: "https://south-plus.net/read.php?tid-20-uid-100.html")!)
    XCTAssertTrue(library.recordVisiblePosts(["post_9008"], in: filtered))
    XCTAssertEqual(library.threads.count, 1)
    XCTAssertEqual(library.threads["20"]?.viewedMaximum, 8)
  }
  func testBlockedPostsMissingFloorsAndForeignPagesAreIgnored() {
    var library = LibraryDocument(site: .south)
    var loaded = page([1, 2, 3, 4])
    loaded.posts[1].authorID = "200"
    loaded.posts[2].number = ""
    loaded.posts[3].number = "#-1"
    library.blockAuthor(id: "200", name: "Blocked")
    XCTAssertTrue(library.recordVisiblePosts(Set(loaded.posts.map(\.id)), in: loaded))
    XCTAssertEqual(library.threads["20"]?.viewedMaximum, 1)
    var foreign = page([99], url: URL(string: "https://simpcity.cr/threads/example.20/")!)
    XCTAssertFalse(library.recordVisiblePosts(["post_9099"], in: foreign))
    foreign.url = url; foreign.kind = .threads
    XCTAssertFalse(library.recordVisiblePosts(["post_9099"], in: foreign))
    var other = LibraryDocument(site: .simp)
    XCTAssertFalse(other.recordVisiblePosts(["post_9001"], in: loaded))
  }
  func testLegacySnapshotsAreNotMigratedAsViewedFloorsAndNewProgressPersists() throws {
    let name = "SouthReadingProgressTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let json = #"{"version":1,"site":"south","bookmarks":[],"recent":[{"url":"https://south-plus.net/read.php?tid=20","title":"Example"}],"threads":{"20":{"seenMaximum":100,"latestMaximum":108}}}"#
    defaults.set(json, forKey: LibraryDocument.key(for: .south))
    var library = try LibraryDocument.load(from: defaults, site: .south)
    XCTAssertNil(library.threads["20"]?.displayedReadMaximum(for: .south))
    XCTAssertEqual(library.threads["20"]?.updated, true)
    XCTAssertTrue(library.recordVisiblePosts(["post_9002"], in: page([0, 1, 2, 3])))
    try library.save(to: defaults)
    let restored = try LibraryDocument.load(from: defaults, site: .south)
    XCTAssertEqual(restored.threads["20"]?.viewedMaximum, 2)
    XCTAssertEqual(restored.threads["20"]?.seenMaximum, 100)
    XCTAssertEqual(restored.threads["20"]?.updated, true)
    XCTAssertEqual(restored.recent.count, 1)
  }
  func testOriginalPostZeroIsValidAndRepeatedCallbacksAreNoOps() {
    var state = ThreadReadState()
    XCTAssertFalse(state.viewed(maximum: -1))
    XCTAssertTrue(state.viewed(maximum: 0))
    XCTAssertFalse(state.viewed(maximum: 0))
    XCTAssertTrue(state.viewed(maximum: 8))
    XCTAssertFalse(state.viewed(maximum: 2))
    XCTAssertEqual(state.viewedMaximum, 8)
  }
}
