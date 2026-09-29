import Foundation
import XCTest
@testable import ForumCore

final class SouthFollowingTests: XCTestCase {
  private let followedAt = Date(timeIntervalSince1970: 100)
  private func thread(_ id: Int) -> URL { URL(string: "https://south-plus.net/read.php?tid-\(id).html")! }
  private func topics(_ ids: [Int], author: String = "101") -> ForumPage {
    ForumPage(url: SouthSitePolicy.authorTopics(author)!, title: "Sample author - Threads", kind: .threads,
              entries: ids.map { ForumEntry(title: "Topic \($0)", url: thread($0), subtitle: "Board and date",
                                            authorID: author, authorName: "Sample author") },
              posts: [], pageNumber: 1)
  }
  private func followedLibrary() -> LibraryDocument {
    var library = LibraryDocument(site: .south)
    library.followAuthor(id: "101", name: "Author", at: followedAt)
    return library
  }
  func testOnlyThreeUniqueLatestTopicsAreStoredAndRefreshingDoesNotReadThem() throws {
    var library = followedLibrary()
    XCTAssertTrue(library.updateFollowing(topics([5, 5, 4, 3, 2]), authorID: "101", followedAt: followedAt))
    library.pruneTracking()
    let author = try XCTUnwrap(library.following.first)
    XCTAssertEqual(author.topics.compactMap { SitePolicy.threadKey($0.url) }, ["5", "4", "3"])
    XCTAssertEqual(author.name, "Sample author")
    XCTAssertTrue(author.topics.allSatisfy { library.isUnreadSouthThread($0.url) })
    XCTAssertTrue(library.recent.isEmpty)
    XCTAssertTrue(library.threads.isEmpty)
    XCTAssertTrue(library.hasRefreshTargets)
    XCTAssertEqual(library.presentations.count, 3)
    XCTAssertEqual(library.presentations["5"]?.authorName, "Sample author")
  }
  func testSuccessfulVisitClearsNewAcrossURLVariantsAndRecentEviction() throws {
    var library = followedLibrary()
    let laterPage = URL(string: "https://south-plus.net/read.php?tid=5&uid=101&page=48#post-900")!
    library.remember(SavedPage(url: laterPage, title: "Read elsewhere"))
    for id in 20...35 { library.remember(SavedPage(url: thread(id), title: "Other topic")) }
    XCTAssertFalse(library.recent.contains { SitePolicy.threadKey($0.url) == "5" })
    library.updateFollowing(topics([5, 4, 3]), authorID: "101", followedAt: followedAt)
    XCTAssertFalse(library.isUnreadSouthThread(thread(5)))
    XCTAssertTrue(library.isUnreadSouthThread(thread(4)))
    library.recent = []
    library.pruneTracking()
    let restored = try JSONDecoder().decode(LibraryDocument.self, from: JSONEncoder().encode(library))
    XCTAssertFalse(restored.isUnreadSouthThread(thread(5)))
    XCTAssertEqual(restored.following.first?.topics.count, 3)
    XCTAssertEqual(restored.subtitle(for: SavedPage(url: laterPage, title: "Saved")), "Sample author")
  }
  func testLegacyLibraryMigratesKnownReadsButNotUnopenedBookmarks() throws {
    let json = #"{"version":1,"site":"south","bookmarks":[{"url":"https://south-plus.net/read.php?tid-4.html","title":"Saved"}],"recent":[{"url":"https://south-plus.net/read.php?tid-5-page-2.html","title":"Visited"}],"threads":{"6":{"seenMaximum":12},"4":{"latestMaximum":42}},"presentations":{"5":{"tags":[],"authorID":"101"}}}"#
    let library = try JSONDecoder().decode(LibraryDocument.self, from: Data(json.utf8))
    XCTAssertTrue(library.following.isEmpty)
    XCTAssertFalse(library.isUnreadSouthThread(thread(5)))
    XCTAssertFalse(library.isUnreadSouthThread(thread(6)))
    XCTAssertTrue(library.isUnreadSouthThread(thread(4)))
    XCTAssertNil(library.subtitle(for: SavedPage(url: thread(5), title: "Old bookmark")))
  }
  func testAuthorSubtitleUsesOwnerAndKeepsItWhenReadingReplyPages() throws {
    var library = LibraryDocument(site: .south)
    let saved = SavedPage(url: thread(5), title: "Topic")
    library.toggle(saved)
    var page = ForumPage(url: thread(5), title: "Topic", kind: .posts, entries: [],
                         posts: [ForumPost(id: "owner", author: "Creator", date: "", number: "#0", blocks: [], authorID: "101")],
                         pageNumber: 1)
    library.capturePresentation(page)
    page.url = SouthSitePolicy.pageURL(thread(5), number: 2)!
    page.posts = [ForumPost(id: "reply", author: "Reply author", date: "", number: "#40", blocks: [], authorID: "202")]
    library.capturePresentation(page)
    library.pruneTracking()
    XCTAssertEqual(library.subtitle(for: saved), "Creator")
    XCTAssertNil(library.subtitle(for: SavedPage(url: SouthSitePolicy.start, title: "Directory")))
    XCTAssertNil(library.subtitle(for: SavedPage(url: SouthSitePolicy.authorTopics("101")!, title: "Author topics")))
  }
  func testInvalidOrStaleRefreshCannotReplaceLastGoodTopics() throws {
    var library = followedLibrary()
    library.updateFollowing(topics([5, 4, 3]), authorID: "101", followedAt: followedAt)
    let previous = library.followedAuthors["101"]
    var later = topics([2, 1])
    later.url = SouthSitePolicy.pageURL(later.url, number: 2)!
    later.pageNumber = 2
    XCTAssertFalse(library.updateFollowing(later, authorID: "101", followedAt: followedAt))
    XCTAssertFalse(library.updateFollowing(topics([100], author: "202"), authorID: "101", followedAt: followedAt))
    var mismatchedRows = topics([100])
    mismatchedRows.entries[0].authorID = "202"
    XCTAssertFalse(library.updateFollowing(mismatchedRows, authorID: "101", followedAt: followedAt))
    XCTAssertEqual(library.followedAuthors["101"], previous)
    library.unfollowAuthor("101")
    XCTAssertFalse(library.updateFollowing(topics([100]), authorID: "101", followedAt: followedAt))
    let newer = followedAt.addingTimeInterval(1)
    library.followAuthor(id: "101", name: "Re-followed", at: newer)
    XCTAssertFalse(library.updateFollowing(topics([100]), authorID: "101", followedAt: followedAt))
    XCTAssertTrue(library.followedAuthors["101"]!.topics.isEmpty)
  }
  func testExplicitEmptyAuthorPageClearsOldTopicsButKeepsReadHistory() {
    var library = followedLibrary()
    library.updateFollowing(topics([5, 4, 3]), authorID: "101", followedAt: followedAt)
    library.remember(SavedPage(url: thread(5), title: "Visited"))
    XCTAssertTrue(library.updateFollowing(topics([]), authorID: "101", followedAt: followedAt))
    library.pruneTracking()
    XCTAssertTrue(library.following[0].topics.isEmpty)
    XCTAssertNotNil(library.following[0].checkedAt)
    XCTAssertFalse(library.isUnreadSouthThread(thread(5)))
  }
  func testBlockingUnfollowsAndSimpcityCannotShareFollowingState() {
    var library = followedLibrary()
    library.blockAuthor(id: "101", name: "Blocked")
    library.followAuthor(id: "101", name: "Still blocked")
    library.followAuthor(id: "0", name: "Invalid")
    library.followAuthor(id: "101&action=edit", name: "Invalid")
    XCTAssertTrue(library.following.isEmpty)
    XCTAssertFalse(library.updateFollowing(topics([5]), authorID: "101", followedAt: followedAt))
    var simp = LibraryDocument()
    simp.followAuthor(id: "101", name: "Foreign")
    XCTAssertTrue(simp.following.isEmpty)
    XCTAssertFalse(simp.isUnreadSouthThread(thread(5)))
    let forum = SavedPage(url: URL(string: "https://simpcity.cr/forums/sample.12/")!, title: "Simp")
    XCTAssertEqual(simp.subtitle(for: forum), "/forums/sample.12")
  }
}
