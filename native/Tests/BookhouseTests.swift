import Foundation
import XCTest
@testable import ForumCore

final class BookhouseTests: XCTestCase {
  func testCatalogExtractsRepostedAuthorAndCategoriesWithoutChangingStoredTitle() throws {
    let subject = "\u{3010}A novel\u{3011}(1-11) \u{4F5C}\u{8005}\u{FF1A} Writer \u{300E}Campus\u{300F}\u{300E}Romance\u{300F}\u{300E}Campus\u{300F}"
    let view = BookhouseTitlePresentation(title: subject, postingAuthor: "Uploader")
    XCTAssertEqual(view.title, "\u{3010}A novel\u{3011}(1-11)")
    XCTAssertEqual(view.author, "Writer")
    XCTAssertEqual(view.tags, ["Campus", "Romance"])
    let html = "<h1 class='main-title'>\(subject)</h1><div class='subtitle-line'><span class='sender'><a>Uploader</a> 2026-09-30 10:20</span></div><div id='content-section'><pre>Original prose.</pre></div>"
    let page = try ForumParser().parse(html, url: try XCTUnwrap(BookhouseSitePolicy.thread("20")))
    XCTAssertEqual(page.title, subject)
    XCTAssertEqual(page.posts.first?.author, "Uploader")
  }

  func testCatalogTitleSupportsASCIIColonAndFallsBackWhenAuthorPatternIsIncomplete() {
    let marker = "\u{4F5C}\u{8005}"
    let start = "\u{300E}", end = "\u{300F}"
    XCTAssertEqual(BookhouseTitlePresentation(title: "Book \(marker): Writer\(start)Tag\(end)", postingAuthor: "Account").author, "Writer")
    let fallback = BookhouseTitlePresentation(title: "Book \(marker): Writer", postingAuthor: "Account")
    XCTAssertEqual(fallback.author, "Account")
    XCTAssertEqual(fallback.title, "Book \(marker): Writer")
    let onlyTag = BookhouseTitlePresentation(title: "\(start)Tag\(end)", postingAuthor: "Account")
    XCTAssertEqual(onlyTag.title, "\(start)Tag\(end)")
    XCTAssertTrue(onlyTag.tags.isEmpty)
  }

  private let start = BookhouseSitePolicy.start
  func testLibraryKeepsSavedBooksWithoutCheckingThreadUpdates() throws {
    var library = LibraryDocument(site: .bookhouse)
    let url = try XCTUnwrap(BookhouseSitePolicy.thread("20"))
    library.remember(SavedPage(url: url, title: "Book"))
    XCTAssertEqual(library.trackedThreads, [url])
    XCTAssertFalse(library.hasRefreshTargets)
    XCTAssertFalse(ForumSite.bookhouse.supportsThreadUpdates)
    XCTAssertNil(ThreadReadState(seenMaximum: 5, latestMaximum: 10).displayedReadMaximum(for: .bookhouse))
    XCTAssertTrue(ForumSite.south.supportsThreadUpdates)
    XCTAssertTrue(ForumSite.simp.supportsThreadUpdates)
  }
  private func url(_ query: String) -> URL { URL(string: "https://www.cool18.com/bbs4/index.php?" + query)! }
  private let rows = #"[{"tid":"30","rootid":"0","uptid":"0","uid":"101","username":"Writer A","subject":"<b>A quiet library</b>","dateline":"09/30/26"},{"tid":"35","rootid":"30","uptid":"30","username":"Reader","subject":"A reply"},{"tid":"20","rootid":"0","uptid":"0","uid":"102","username":"Writer B","subject":"Another book"}]"#

  func testGuestSiteHasItsOwnRouteAndLibraryIdentity() throws {
    XCTAssertEqual(ForumSite(url: start), .bookhouse)
    XCTAssertFalse(ForumSite.bookhouse.supportsLogin)
    XCTAssertNotEqual(LibraryDocument.key(for: .bookhouse), LibraryDocument.key(for: .south))
    XCTAssertNotEqual(LibraryDocument.key(for: .bookhouse), LibraryDocument.key(for: .simp))
    let thread = try XCTUnwrap(BookhouseSitePolicy.thread("20"))
    XCTAssertEqual(SitePolicy.threadKey(thread), "20")
    XCTAssertEqual(SitePolicy.threadRoot(thread), thread)
    XCTAssertFalse(ForumSite.south.accepts(thread))
    XCTAssertFalse(ForumSite.simp.accepts(thread))
    let cookie = try XCTUnwrap(HTTPCookie(properties: [.name: "fixture", .value: "synthetic", .domain: ".cool18.com", .path: "/"]))
    XCTAssertFalse(ForumSite.bookhouse.domainMatches(cookie))
    let request = try ForumRequest.page(site: .bookhouse, url: thread, userAgent: "Desktop-fixture", cookies: [cookie])
    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    XCTAssertFalse(request.httpShouldHandleCookies)
  }

  func testRouteAllowlistRejectsActionsForeignSitesAndAmbiguousQueries() {
    for query in ["app=forum&act=postnew", "app=forum&act=vote&tid=20", "app=sys&act=threadmanage&tid=20",
                  "app=forum&act=threadview&tid=20&tid=21", "app=forum&act=threadview&tid=0",
                  "app=forum&act=threadview&tid=20&action=edit", "app=forum&act=ajax&mtid=20&aifilter=1",
                  "app=forum&act=threadsearch&keywords=a&p=100000", "app=forum&act=threadsearch&keywords=a&bbsdr=bbs5"] {
      XCTAssertFalse(BookhouseSitePolicy.readable(url(query)), query)
    }
    for value in ["https://www.cool18.com/bbs5/index.php", "https://www.cool18.com.example.org/bbs4/index.php",
                  "https://user@www.cool18.com/bbs4/index.php", "https://www.cool18.com:444/bbs4/index.php"] {
      XCTAssertFalse(BookhouseSitePolicy.readable(URL(string: value)!))
    }
    XCTAssertNil(BookhouseSitePolicy.resolve("javascript:alert(1)", from: start))
    XCTAssertNotNil(BookhouseSitePolicy.resolve("http://cool18.com/bbs4/index.php?app=forum&act=threadview&tid=20", from: start, internalOnly: true))
  }

  func testEmbeddedDataProducesRootBooksRatherThanDuplicateReplyRows() throws {
    let html = "<div id='d_list'><ul class='thread-list'></ul></div><script>const _PageData = \(rows);</script>"
    let page = try ForumParser().parse(html, url: start)
    XCTAssertEqual(page.entries.count, 2)
    XCTAssertEqual(page.entries.map(\.title), ["A quiet library", "Another book"])
    XCTAssertEqual(page.entries.first?.authorName, "Writer A")
    XCTAssertEqual(BookhouseSitePolicy.route(try XCTUnwrap(page.next))?.parameters["mtid"], "20")
    XCTAssertNil(page.loggedIn)
  }

  func testCursorOnlyAdvancesAndAnEmptyResponseEndsTheList() throws {
    let cursor = try XCTUnwrap(BookhouseSitePolicy.cursor("50"))
    let page = try ForumParser().parse(rows, url: cursor)
    XCTAssertEqual(BookhouseSitePolicy.route(try XCTUnwrap(page.next))?.parameters["mtid"], "20")
    let repeatPage = try ForumParser().parse(rows, url: try XCTUnwrap(BookhouseSitePolicy.cursor("20")))
    XCTAssertNil(repeatPage.next)
    XCTAssertNil(try ForumParser().parse("[]", url: cursor).next)
    XCTAssertThrowsError(try ForumParser().parse("<html>Verification</html>", url: cursor))
  }

  func testReplyEndpointKeepsContinuationsAndRepliesAsReadableEntries() throws {
    let target = try XCTUnwrap(BookhouseSitePolicy.replies(try XCTUnwrap(BookhouseSitePolicy.thread("30"))))
    let page = try ForumParser().parse(rows, url: target)
    XCTAssertEqual(page.entries.count, 3)
    XCTAssertEqual(page.entries[1].title, "A reply")
    XCTAssertNil(page.next)
    XCTAssertNil(BookhouseSitePolicy.threadKey(target))
  }

  func testEmbeddedJSONHandlesQuotedBracketsWithoutExecutingExpressions() {
    let source = #"const _PageData = [{"subject":"brackets ] } and quote \" preserved"}]; runUntrustedCode();"#
    let data = BookhouseParser.embeddedJSON("_PageData", in: source) as? [[String: String]]
    XCTAssertEqual(data?.first?["subject"], "brackets ] } and quote \" preserved")
    XCTAssertNil(BookhouseParser.embeddedJSON("_PageData", in: "const _PageData = runUntrustedCode();"))
    XCTAssertNil(BookhouseParser.embeddedJSON("_PageData", in: "const _PageData = [{broken:1}];"))
  }

  func testNovelPreservesParagraphsAndExcludesPageChromeAndAds() throws {
    let html = """
    <script>const threadInfo = {"tid":20,"uid":"101","username":"Writer"};</script>
    <h1 class="main-title">An ordinary story</h1>
    <div class="subtitle-line"><span class="sender"><a>Writer</a> 2026-09-30 10:20</span></div>
    <div id="content-section"><pre>First paragraph.

    Second <b>bold</b> paragraph.<br>Third paragraph.</pre>
    <div class="view_ad_incontent">Unwanted advertising</div>
    <div class="ai-detection-feedback"><button>Feedback</button>Unwanted controls</div>
    <script>untrusted()</script><p><a href="index.php?app=forum&amp;act=threadview&amp;tid=21">Next chapter</a></p></div>
    <div class="view_tools_box">Other tools</div>
    """
    let page = try ForumParser().parse(html, url: try XCTUnwrap(BookhouseSitePolicy.thread("20")))
    XCTAssertEqual(page.kind, .posts)
    XCTAssertEqual(page.title, "An ordinary story")
    let post = try XCTUnwrap(page.posts.first)
    XCTAssertEqual(post.author, "Writer")
    XCTAssertEqual(post.date, "2026-09-30 10:20")
    XCTAssertTrue(post.blocks.allSatisfy { $0.kind == .paragraph })
    let text = post.blocks.flatMap(\.runs).map(\.text).joined(separator: " ")
    for unwanted in ["Unwanted", "untrusted", "Other tools"] { XCTAssertFalse(text.contains(unwanted)) }
    XCTAssertEqual(post.blocks.count, 4)
    XCTAssertTrue(post.blocks[1].runs.contains { $0.bold && $0.text == "bold" })
    XCTAssertEqual(post.blocks.last?.runs.last?.url.flatMap(BookhouseSitePolicy.threadKey), "21")
  }

  func testLongPlainTextIsSplitIntoBoundedLayoutsWithoutLosingCharacters() throws {
    let text = String(repeating: "a", count: 7000)
    let html = "<h1 class='main-title'>Long novel</h1><div id='content-section'><pre>\(text)</pre></div>"
    let page = try ForumParser().parse(html, url: try XCTUnwrap(BookhouseSitePolicy.thread("20")))
    let blocks = try XCTUnwrap(page.posts.first).blocks
    XCTAssertTrue(blocks.allSatisfy { $0.runs.map(\.text).joined().count <= 1600 })
    XCTAssertEqual(blocks.flatMap(\.runs).map(\.text).joined(), text)
  }

  func testSearchUsesObservedGetFormAndParsesNumberedPagination() throws {
    let target = try XCTUnwrap(BookhouseSitePolicy.search("a & b"))
    XCTAssertEqual(BookhouseSitePolicy.route(target)?.parameters["keywords"], "a & b")
    let second = try XCTUnwrap(BookhouseSitePolicy.pageURL(target, number: 2))
    let html = """
    <ul class="post-list thread-list"><li class="post-item"><a href="index.php?app=forum&amp;act=threadview&amp;tid=20">A book</a><a href="#">Writer</a></li></ul>
    <nav class="pagination-bar"><a href="\(second.absoluteString)">Next</a></nav>
    """
    let page = try ForumParser().parse(html, url: target)
    XCTAssertEqual(page.entries.first?.title, "A book")
    XCTAssertEqual(page.next, second)
    XCTAssertNil(page.previous)
    XCTAssertEqual(SitePolicy.pageNumber(second), 2)
    XCTAssertEqual(BookhouseSitePolicy.pageRoot(second), BookhouseSitePolicy.pageRoot(target))
  }

  func testBookMetadataAndReadingPositionDoNotLeakToOtherLibraries() throws {
    let target = try XCTUnwrap(BookhouseSitePolicy.thread("20"))
    let post = ForumPost(id: "sample", author: "Writer", date: "", number: "", blocks: [], authorID: "101")
    let page = ForumPage(url: target, title: "Sample novel", kind: .posts, entries: [], posts: [post], pageNumber: 1)
    var bookhouse = LibraryDocument(site: .bookhouse)
    bookhouse.remember(SavedPage(url: target, title: page.title))
    bookhouse.capturePresentation(page)
    XCTAssertEqual(bookhouse.subtitle(for: SavedPage(url: target, title: page.title)), "Writer")
    var south = LibraryDocument(site: .south)
    south.remember(SavedPage(url: target, title: page.title))
    XCTAssertTrue(south.recent.isEmpty)
    let cache = PageCache()
    cache.store(page); cache.savePosition("paragraph-10", for: target)
    XCTAssertEqual(cache.value(for: target)?.visibleID, "paragraph-10")
    XCTAssertNil(cache.value(for: URL(string: "https://south-plus.net/read.php?tid=20")!))
  }
}
