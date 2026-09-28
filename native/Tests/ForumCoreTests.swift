import Foundation
import XCTest
@testable import ForumCore

final class ForumCoreTests: XCTestCase {
  func testForumRowsAndUnreadCanonicalization() throws {
    let source = #"<html data-template="forum_view"><h1 class="p-title-value">Photography</h1><div class="structItem--thread"><div class="structItem-title"><a class="labelLink">Featured</a><a href="/threads/example.123/unread?new=1">Example</a></div><i class="structItem-status--sticky"></i></div></html>"#
    let page = try ForumParser().parse(source, url: URL(string: "https://simpcity.cr/forums/example.12/")!)
    XCTAssertEqual(page.entries.count, 1)
    XCTAssertEqual(page.entries.first?.url.absoluteString, "https://simpcity.cr/threads/example.123/")
    XCTAssertTrue(page.entries[0].pinned)
  }
  func testPostBlocksPreserveBothMediaPathsAndRemoveAds() throws {
    let source = #"<html data-template="thread_view" data-logged-in="true"><h1 class="p-title-value">Sample</h1><article id="post-7" class="message--post"><div class="message-name"><a class="username">Reader</a></div><div class="message-attribution-opposite"><a>#42</a></div><div class="message-body"><div class="bbWrapper"><p>Hello <b>world</b></p><div class="advertisement">hidden ad</div><img data-src="/image.jpg" width="600" height="400"><iframe src="https://turbo.cr/embed/example"></iframe><iframe src="https://cyberdrop.cr/e/example"></iframe><blockquote>Quoted text</blockquote><div class="bbCodeSpoiler"><div class="bbCodeSpoiler-content">Hidden text</div></div></div></div></article><a class="pageNav-jump--next" href="/threads/example.1/page-2">Next</a></html>"#
    let page = try ForumParser().parse(source, url: URL(string: "https://simpcity.cr/threads/example.1/")!)
    XCTAssertEqual(page.posts.count, 1)
    let post = page.posts[0]
    XCTAssertEqual(post.number, "#42")
    XCTAssertEqual(post.blocks.filter { $0.kind == .media }.compactMap { $0.url?.host }, ["turbo.cr", "cyberdrop.cr"])
    XCTAssertEqual(post.blocks.first { $0.kind == .image }?.aspectRatio, 1.5)
    XCTAssertFalse(post.blocks.flatMap(\.runs).contains { $0.text.contains("hidden ad") })
    XCTAssertTrue(post.blocks.contains { $0.kind == .quote })
    XCTAssertTrue(post.blocks.contains { $0.kind == .spoiler })
    XCTAssertTrue(page.loggedIn)
    XCTAssertNotNil(page.next)
  }
  func testChallengesAndUnsupportedPagesAreNotEmptySuccesses() {
    XCTAssertThrowsError(try ForumParser().parse("<title>Just a moment</title>", url: SitePolicy.base)) { XCTAssertEqual($0 as? ReaderFailure, .verification) }
    XCTAssertThrowsError(try ForumParser().parse("<html data-template='thread_view'></html>", url: SitePolicy.base))
    XCTAssertThrowsError(try ForumParser().parse("", url: SitePolicy.base, status: 429)) { XCTAssertEqual($0 as? ReaderFailure, .rateLimit) }
  }
  func testReadPolicyRejectsMutationAndForeignOrigins() {
    for address in ["https://simpcity.cr/logout/", "https://simpcity.cr/threads/x.1/?delete=1", "https://simpcity.cr/threads/x.1/?page=1&page=2", "https://evil.test/threads/x.1/", "https://user@simpcity.cr/"] {
      XCTAssertFalse(SitePolicy.readable(URL(string: address)!))
    }
    XCTAssertTrue(SitePolicy.readable(URL(string: "https://simpcity.cr/threads/x.1/page-3#post-8")!))
  }
  func testPosterPrefersActualPlayerOverSocialMetadata() {
    let html = #"<meta property="og:image" content="/fallback.jpg"><video id="main-video" poster="/poster.jpg"></video>"#
    XCTAssertEqual(ForumParser.poster(html, page: URL(string: "https://turbo.cr/embed/example")!)?.path, "/poster.jpg")
  }
  func testLegacyLibraryMigrationAndHistoryDeduplication() throws {
    let defaults = UserDefaults(suiteName: "ForumCoreTests.\(UUID())")!
    defaults.set(#"{"version":1,"bookmarks":[{"url":"https://simpcity.cr/threads/example.1/","title":"Example"}],"recent":[]}"#, forKey: LibraryDocument.key)
    var document = try LibraryDocument.load(from: defaults)
    XCTAssertEqual(document.bookmarks.count, 1)
    document.remember(SavedPage(url: URL(string: "https://simpcity.cr/threads/example.1/page-2")!, title: "Example"))
    document.remember(SavedPage(url: URL(string: "https://simpcity.cr/threads/example.1/page-3#post-9")!, title: "Example"))
    XCTAssertEqual(document.recent.count, 1)
    XCTAssertEqual(document.recent[0].url.fragment, "post-9")
    try document.save(to: defaults)
    XCTAssertEqual(try LibraryDocument.load(from: defaults).recent, document.recent)
  }
  func testMalformedLibraryIsPreserved() {
    let defaults = UserDefaults(suiteName: "ForumCoreTests.\(UUID())")!
    defaults.set("invalid", forKey: LibraryDocument.key)
    XCTAssertThrowsError(try LibraryDocument.load(from: defaults))
    XCTAssertEqual(defaults.string(forKey: LibraryDocument.key), "invalid")
  }
  private func threadHTML(_ numbers: [Int], navigation: String = "") -> String {
    let posts = numbers.map { number in
      "<article id='post-\(9000 + number)' class='message--post'><div class='message-attribution-opposite'><a>#\(number)</a></div><div class='message-body'><div class='bbWrapper'>Post</div></div></article>"
    }.joined()
    return "<html data-template='thread_view'><h1 class='p-title-value'>Example</h1>\(posts)\(navigation)</html>"
  }
  func testMaximumFloorRequiresLastPageAndDoesNotUsePostID() throws {
    let navigation = "<ul class='pageNav-main'><li class='pageNav-page pageNav-page--current'><a href='/threads/example.123/'>1</a></li><li class='pageNav-page'><a href='/threads/example.123/page-6'>6</a></li></ul><a class='pageNavSimple-el--next' href='/threads/example.123/page-2'>Next</a>"
    let first = try ForumParser().parse(threadHTML([1, 20], navigation: navigation), url: URL(string: "https://simpcity.cr/threads/example.123/")!)
    XCTAssertNil(first.maximumPostNumber)
    XCTAssertEqual(first.lastPage?.lastPathComponent, "page-6")
    let last = try ForumParser().parse(threadHTML([101, 108]), url: URL(string: "https://simpcity.cr/threads/example.123/page-6")!)
    XCTAssertEqual(last.pageNumber, 6)
    XCTAssertEqual(last.maximumPostNumber, 108)
  }
  func testLastPageWithoutNextStillPreventsFalseMaximum() throws {
    let navigation = "<a class='pageNavSimple-el--last' href='/threads/example.123/page-7'>Last</a><li class='pageNav-page'><a href='/threads/foreign.456/page-200'>200</a></li>"
    let page = try ForumParser().parse(threadHTML([80], navigation: navigation), url: URL(string: "https://simpcity.cr/threads/example.123/page-4")!)
    XCTAssertNil(page.maximumPostNumber)
    XCTAssertEqual(page.lastPage?.lastPathComponent, "page-7")
    let unknown = try ForumParser().parse("<html data-template='thread_view'><article class='message--post'><div class='message-body'><div class='bbWrapper'>Post</div></div></article></html>", url: URL(string: "https://simpcity.cr/threads/example.123/")!)
    XCTAssertNil(unknown.maximumPostNumber)
  }
  func testThreadUpdateLifecycleAndPersistence() throws {
    let defaults = UserDefaults(suiteName: "ForumCoreTests.\(UUID())")!
    var library = LibraryDocument()
    let page = SavedPage(url: URL(string: "https://simpcity.cr/threads/example.123/page-2#post-8")!, title: "Example")
    library.remember(page)
    library.threads["123", default: ThreadReadState()].opened(maximum: 100)
    library.threads["123", default: ThreadReadState()].checked(maximum: 108)
    XCTAssertTrue(library.threads["123"]!.updated)
    XCTAssertEqual(library.threads["123"]?.seenMaximum, 100)
    try library.save(to: defaults)
    library = try LibraryDocument.load(from: defaults)
    XCTAssertTrue(library.threads["123"]!.updated)
    library.threads["123"]!.opened(maximum: 108)
    XCTAssertFalse(library.threads["123"]!.updated)
    library.threads["123"]!.checked(maximum: 106)
    XCTAssertFalse(library.threads["123"]!.updated)
    XCTAssertEqual(library.recent.first?.url, page.url)
  }
  func testLegacyRefreshDoesNotInventReadBaselineAndTrackingDeduplicatesThreads() throws {
    let defaults = UserDefaults(suiteName: "ForumCoreTests.\(UUID())")!
    defaults.set(#"{"version":1,"bookmarks":[{"url":"https://simpcity.cr/threads/old-name.123/page-3","title":"Saved"}],"recent":[]}"#, forKey: LibraryDocument.key)
    var library = try LibraryDocument.load(from: defaults)
    XCTAssertTrue(library.threads.isEmpty)
    library.threads["123", default: ThreadReadState()].checked(maximum: 108)
    XCTAssertNil(library.threads["123"]?.seenMaximum)
    XCTAssertFalse(library.threads["123"]!.updated)
    library.remember(SavedPage(url: URL(string: "https://simpcity.cr/threads/new-name.123/page-6#post-9")!, title: "Renamed"))
    library.remember(SavedPage(url: URL(string: "https://simpcity.cr/forums/example.123/")!, title: "Forum"))
    XCTAssertEqual(library.trackedThreads.count, 1)
    XCTAssertNil(library.trackedThreads.first?.fragment)
    XCTAssertEqual(library.trackedThreads.first?.path, "/threads/new-name.123/")
    library.recent = []
    library.pruneTracking()
    XCTAssertNotNil(library.threads["123"])
    library.bookmarks = []
    library.pruneTracking()
    XCTAssertTrue(library.threads.isEmpty)
  }
}
