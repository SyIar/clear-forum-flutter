import Foundation
import XCTest
@testable import ForumCore

final class BookhouseSearchTests: XCTestCase {
  func testHighlightedTerminalAuthorIsDisplayedInsteadOfPostingAccount() throws {
    let url = try XCTUnwrap(BookhouseSitePolicy.search("Novel"))
    let author = "\u{9752}\u{7389}\u{6D6E}\u{5C18}"
    let title = "\u{3010}Novel\u{3011}\u{FF08}27\u{FF09}"
    let html = """
    <ul class="post-list thread-list"><li class="l-m1">
      <a href="index.php?app=forum&amp;act=threadview&amp;tid=20"><b>\(title)\u{4F5C}\u{8005}\u{FF1A}\u{9752}<span class="keyword">\u{7389}</span>\u{6D6E}<span class="keyword">\u{5C18}</span></b></a>
      - <font color="black">Uploader</font><i> 10/04/25 </i>
    </li></ul>
    """
    let page = try ForumParser().parse(html, url: url)
    let entry = try XCTUnwrap(page.entries.first)
    let view = BookhouseTitlePresentation(title: entry.title, postingAuthor: entry.authorName ?? "")
    XCTAssertEqual(view.title, title)
    XCTAssertEqual(view.author, author)
    XCTAssertTrue(view.tags.isEmpty)
    XCTAssertEqual(entry.authorName, "Uploader")
    XCTAssertEqual(entry.title, title + "\u{4F5C}\u{8005}\u{FF1A}" + author)
    XCTAssertEqual(entry.postedAt, "10/04/25")
  }

  func testSearchExcludesFeaturedPostsAndKeepsHighlightedTitleAuthorAndDate() throws {
    let url = try XCTUnwrap(BookhouseSitePolicy.search("test"))
    let html = """
    <ul class="post-list"><li class="post-item">
      <a href="index.php?app=forum&amp;act=threadview&amp;tid=99">Unrelated featured book</a>
    </li></ul>
    <ul class="post-list thread-list">
      <li class="l-m1"><a href="index.php?app=forum&amp;act=threadview&amp;tid=20"><b>A <span class="keyword">test</span> book</b></a>
        - <font color="black">Writer A</font><i> 09/20/26 </i></li>
      <li class="l-m1"><a href="index.php?app=forum&amp;act=threadview&amp;tid=21">Another test</a>
        - <font color="black">Writer B</font><i> 09/19/26 </i></li>
    </ul>
    """
    let page = try ForumParser().parse(html, url: url)
    XCTAssertEqual(page.entries.count, 2)
    XCTAssertEqual(page.entries.map { SitePolicy.threadKey($0.url) }, ["20", "21"])
    XCTAssertEqual(page.entries[0].title, "A test book")
    XCTAssertEqual(page.entries[0].authorName, "Writer A")
    XCTAssertEqual(page.entries[0].postedAt, "09/20/26")
    XCTAssertEqual(page.entries[1].authorName, "Writer B")
  }

  func testPaginationIgnoresSubmitDecorationButPreservesSearchFilters() throws {
    let url = try XCTUnwrap(BookhouseSitePolicy.search("test"))
    let query = "index.php?action=search&amp;bbsdr=bbs4&amp;act=threadsearch&amp;app=forum&amp;keywords=test&amp;submit=%E6%9F%A5%E8%AF%A2"
    let html = """
    <ul class="thread-list"><li><a href="index.php?app=forum&amp;act=threadview&amp;tid=20">Book</a></li></ul>
    <nav class="pagination-bar">
      <a href="\(query)&amp;p=0">Previous</a><span class="current">1</span>
      <a href="\(query)&amp;p=2">Next</a>
      <a href="\(query)&amp;first=1&amp;p=50">Different filter</a>
      <a href="index.php?app=forum&amp;act=threadsearch&amp;keywords=other&amp;p=99">Different query</a>
    </nav>
    """
    let page = try ForumParser().parse(html, url: url)
    XCTAssertNil(page.previous)
    XCTAssertEqual(page.totalPages, 2)
    let next = try XCTUnwrap(page.next)
    XCTAssertEqual(BookhouseSitePolicy.pageNumber(next), 2)
    XCTAssertEqual(BookhouseSitePolicy.route(next)?.parameters["keywords"], "test")
    XCTAssertEqual(BookhouseSitePolicy.pageRoot(next), BookhouseSitePolicy.pageRoot(url))
    let last = try ForumParser().parse("<ul class='thread-list'></ul><nav class='pagination-bar'></nav>", url: next)
    XCTAssertEqual(last.previous, BookhouseSitePolicy.pageURL(next, number: 1))
    XCTAssertNil(last.next)
  }

  func testEmptySearchContainerIsValidButUnrelatedHTMLIsNotAnEmptyResult() throws {
    let url = try XCTUnwrap(BookhouseSitePolicy.search("no-match"))
    let page = try ForumParser().parse("<ul class='post-list thread-list'></ul>", url: url)
    XCTAssertTrue(page.entries.isEmpty)
    XCTAssertThrowsError(try ForumParser().parse("<h1>Temporarily unavailable</h1>", url: url))
  }

  func testEmptyTerminalPageStopsEvenWhenSiteRendersAnotherNextLink() throws {
    let first = try XCTUnwrap(BookhouseSitePolicy.search("test"))
    let current = try XCTUnwrap(BookhouseSitePolicy.pageURL(first, number: 3))
    let next = try XCTUnwrap(BookhouseSitePolicy.pageURL(first, number: 4))
    let html = "<ul class='thread-list'></ul><nav class='pagination-bar'><a href='\(next.absoluteString)'>Next</a></nav>"
    let page = try ForumParser().parse(html, url: current)
    XCTAssertNil(page.next)
    XCTAssertEqual(BookhouseSitePolicy.pageNumber(try XCTUnwrap(page.previous)), 2)
  }
}
