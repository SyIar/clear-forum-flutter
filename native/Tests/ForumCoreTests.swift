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
    XCTAssertEqual(page.loggedIn, true)
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
  func testSavedThreadPresentationMigratesAndSurvivesPageAndSlugChanges() throws {
    let defaults = UserDefaults(suiteName: "ForumCoreTests.\(UUID())")!
    defaults.set(#"{"version":1,"bookmarks":[{"url":"https://simpcity.cr/threads/old.123/page-48","title":"My title"}],"recent":[]}"#, forKey: LibraryDocument.key)
    var library = try LibraryDocument.load(from: defaults)
    XCTAssertTrue(library.presentations.isEmpty)
    let url = URL(string: "https://simpcity.cr/threads/new.123/")!
    let cover = URL(string: "https://images.example/cover.jpg")!
    let tags = [ForumTag(title: "Photo", url: URL(string: "https://simpcity.cr/forums/example.12/?prefix_id=3")!)]
    var page = try ForumParser().parse(threadHTML([1]), url: url)
    page.thumbnail = cover
    page.tags = tags
    library.capturePresentation(page)
    library.pruneTracking()
    XCTAssertEqual(library.presentations["123"]?.thumbnail, cover)
    XCTAssertEqual(library.bookmarks.first?.title, "Example")
    XCTAssertEqual(library.bookmarks.first?.url.lastPathComponent, "page-48")
    XCTAssertTrue(library.recent.isEmpty)
    XCTAssertTrue(library.threads.isEmpty)
    library.remember(SavedPage(url: URL(string: "https://simpcity.cr/threads/new.123/page-47")!, title: "New"))
    try library.save(to: defaults)
    let restored = try LibraryDocument.load(from: defaults)
    XCTAssertEqual(restored.presentations["123"]?.tags, tags)
    XCTAssertEqual(restored.presentations["123"]?.thumbnail, cover)
    XCTAssertEqual(restored.recent.count, 1)
  }
  func testPresentationKeepsKnownFieldsAndPrunesUnreferencedThreads() throws {
    var library = LibraryDocument()
    let url = URL(string: "https://simpcity.cr/threads/example.123/")!
    let cover = URL(string: "https://images.example/cover.jpg")!
    let tag = ForumTag(title: "Photo", url: URL(string: "https://simpcity.cr/forums/example.12/?prefix_id=3")!)
    library.toggle(SavedPage(url: url, title: "Saved"))
    library.mergePresentation(ThreadPresentation(thumbnail: cover, tags: [tag]), for: url)
    library.mergePresentation(ThreadPresentation(), for: url)
    library.mergePresentation(ThreadPresentation(thumbnail: URL(string: "https://user:pass@images.example/private.jpg"),
                                               tags: [ForumTag(title: "Unsafe", url: URL(string: "https://simpcity.cr/logout/")!)]), for: url)
    XCTAssertEqual(library.presentations["123"]?.thumbnail, cover)
    XCTAssertEqual(library.presentations["123"]?.tags, [tag])
    let unrelated = URL(string: "https://simpcity.cr/threads/other.456/")!
    library.mergePresentation(ThreadPresentation(thumbnail: cover), for: unrelated)
    library.pruneTracking()
    XCTAssertEqual(library.presentations.count, 1)
    library.toggle(SavedPage(url: url, title: "Saved"))
    library.pruneTracking()
    XCTAssertTrue(library.presentations.isEmpty)
  }
  func testThreadCoverUsesSocialMetadataButRejectsSiteLogo() throws {
    let url = URL(string: "https://simpcity.cr/threads/example.123/")!
    let content = threadHTML([1])
    let cover = "<meta property='og:image' content='https://images.example/cover.jpg'>"
    XCTAssertEqual(try ForumParser().parse(cover + content, url: url).thumbnail?.absoluteString, "https://images.example/cover.jpg")
    let fallback = "<meta property='og:image' content='/data/assets/logo_default/logo.png'><meta name='twitter:image' content='/cover.jpg'>"
    XCTAssertEqual(try ForumParser().parse(fallback + content, url: url).thumbnail?.path, "/cover.jpg")
    let sharedLogo = "<meta property='og:image' content='/branding.png'><div class='p-header-logo'><img src='/branding.png'></div>"
    XCTAssertNil(try ForumParser().parse(sharedLogo + content, url: url).thumbnail)
    XCTAssertNil(try ForumParser().parse(cover + "<html data-template='forum_view'></html>", url: URL(string: "https://simpcity.cr/forums/example.12/")!).thumbnail)
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
    XCTAssertEqual(library.trackedThreads.first?.lastPathComponent, "new-name.123")
    library.recent = []
    library.pruneTracking()
    XCTAssertNotNil(library.threads["123"])
    library.bookmarks = []
    library.pruneTracking()
    XCTAssertTrue(library.threads.isEmpty)
  }
  func testDirectoryThumbnailsUseBackgroundInsteadOfTransparentPlaceholderOrLatestAvatar() throws {
    let source = #"<html data-template="forum_view"><div class="structItem--thread"><div class="structItem-cell--icon"><a class="dcThumbnail"><img style="background-image: url(https://images.example/cover.jpg); background-size: cover" src="data:image/png;base64,placeholder"></a></div><div class="structItem-title"><a href="/threads/example.123/">Example</a></div><div class="structItem-cell--icon structItem-cell--iconEnd"><img src="https://images.example/latest-avatar.jpg"></div></div></html>"#
    let page = try ForumParser().parse(source, url: URL(string: "https://simpcity.cr/forums/example.12/")!)
    XCTAssertEqual(page.entries.first?.thumbnail?.absoluteString, "https://images.example/cover.jpg")
    let legacyHTTP = source.replacingOccurrences(of: "https://images.example/cover.jpg", with: "http://images.example:80/cover.jpg?v=1")
    XCTAssertEqual(try ForumParser().parse(legacyHTTP, url: page.url).entries.first?.thumbnail?.absoluteString, "https://images.example/cover.jpg?v=1")
    let credentialURL = source.replacingOccurrences(of: "https://images.example/cover.jpg", with: "http://user:pass@images.example/cover.jpg")
    XCTAssertNil(try ForumParser().parse(credentialURL, url: page.url).entries.first?.thumbnail)
    let fallback = source.replacingOccurrences(of: "background-image: url(https://images.example/cover.jpg); background-size: cover", with: "")
      .replacingOccurrences(of: "src=\"data:image/png;base64,placeholder\"", with: "data-src=\"/lazy.jpg\" src=\"data:image/png;base64,placeholder\"")
    XCTAssertEqual(try ForumParser().parse(fallback, url: page.url).entries.first?.thumbnail?.path, "/lazy.jpg")
    let noCover = source.replacingOccurrences(of: "background-image: url(https://images.example/cover.jpg); background-size: cover", with: "")
    XCTAssertNil(try ForumParser().parse(noCover, url: page.url).entries.first?.thumbnail)
  }
  func testBreadcrumbsPreserveOrderFragmentsAndSafeDestinations() throws {
    let navigation = "<ul class='p-breadcrumbs'><li><a href='/#category.100'>Category</a></li><li><a href='/forums/example.12/'>Forum</a></li><li><a href='/logout/'>Unsafe</a></li><li><a href='https://outside.example/'>Outside</a></li></ul>"
    let source = threadHTML([1]) + navigation + navigation
    let page = try ForumParser().parse(source, url: URL(string: "https://simpcity.cr/threads/example.123/")!)
    XCTAssertEqual(page.breadcrumbs.map(\.title), ["Category", "Forum"])
    XCTAssertEqual(page.breadcrumbs.first?.url.fragment, "category.100")
    XCTAssertEqual(page.breadcrumbs.last?.url.absoluteString, "https://simpcity.cr/forums/example.12/")
  }
  func testRootCategoryAnchorAndEncodedThreadNavigation() throws {
    let source = "<html data-template='forum_list'><div class='block block--category'><span class='u-anchorTarget' id='category.100'></span><div class='block-container'><div class='node'><h3 class='node-title'><a href='/forums/example.12/'>Example</a></h3></div></div></div></html>"
    let page = try ForumParser().parse(source, url: SitePolicy.base)
    XCTAssertEqual(page.entries.first?.sectionAnchor, "category.100")
    let url = URL(string: "https://simpcity.cr/threads/example-%E6%9D%BE.123/page-3#post-9001")!
    XCTAssertTrue(SitePolicy.readable(url))
    XCTAssertEqual(SitePolicy.threadKey(url), "123")
    XCTAssertEqual(SitePolicy.pageRoot(url), SitePolicy.threadRoot(url))
  }
  func testClickableTagsInDirectoriesAndThreadHeadings() throws {
    let forumURL = URL(string: "https://simpcity.cr/forums/example.12/")!
    let row = #"<div class="structItem--thread"><div class="structItem-title"><a class="labelLink" href="/forums/example.12/?prefix_id[0]=3"><span class="label">Photo</span></a><a class="labelLink" href="/forums/example.12/?prefix_id[0]=18">Travel</a><a href="/threads/example.123/">Example</a></div></div>"#
    let directory = try ForumParser().parse("<html data-template='forum_view'>\(row)</html>", url: forumURL)
    XCTAssertEqual(directory.entries.first?.title, "Example")
    XCTAssertEqual(directory.entries.first?.tags.map(\.title), ["Photo", "Travel"])
    XCTAssertEqual(URLComponents(url: directory.entries[0].tags[0].url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "prefix_id[0]")
    let source = threadHTML([1]).replacingOccurrences(of: "<h1 class='p-title-value'>Example</h1>", with: "<h1 class='p-title-value'><a class='labelLink' href='/forums/example.12/?prefix_id=3'><span class='label'>Photo</span></a><span class='label-append'>&nbsp;</span>Example</h1>")
    let thread = try ForumParser().parse(source, url: URL(string: "https://simpcity.cr/threads/example.123/")!)
    XCTAssertEqual(thread.title, "Example")
    XCTAssertEqual(thread.tags.map(\.title), ["Photo"])
    XCTAssertEqual(thread.tags.first?.url.query, "prefix_id=3")
  }
  func testPrefixFilterAllowsReadOnlyForumQueriesAndPreservesPagination() {
    let root = URL(string: "https://simpcity.cr/forums/example.12/?prefix_id%5B0%5D=3")!
    let next = URL(string: "https://simpcity.cr/forums/example.12/page-2?prefix_id%5B0%5D=3")!
    XCTAssertTrue(SitePolicy.readable(root))
    XCTAssertTrue(SitePolicy.readable(next))
    XCTAssertEqual(SitePolicy.pageRoot(next), root)
    for suffix in ["prefix_id=all", "prefix_id=-1", "prefix_id[99]=3", "prefix_id[0]=3&prefix_id[0]=4", "prefix_id=3&delete=1"] {
      XCTAssertFalse(SitePolicy.readable(URL(string: "https://simpcity.cr/forums/example.12/?\(suffix)")!))
    }
    XCTAssertFalse(SitePolicy.readable(URL(string: "https://simpcity.cr/threads/example.123/?prefix_id=3")!))
  }
}
