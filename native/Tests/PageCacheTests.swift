import Foundation
import XCTest
@testable import ForumCore

final class PageCacheTests: XCTestCase {
  private func page(_ number: Int, title: String = "Example") -> ForumPage {
    ForumPage(url: SitePolicy.pageURL(URL(string: "https://simpcity.cr/threads/example.42/")!, number: number)!,
              title: title, kind: .posts, entries: [], posts: [], pageNumber: number, loggedIn: true)
  }
  func testPageSelectionPreservesFiltersAndRejectsInvalidTargets() throws {
    let forum = URL(string: "https://simpcity.cr/forums/example.12/page-4?prefix_id%5B0%5D=23&order=post_date#entry")!
    let result = try XCTUnwrap(SitePolicy.pageURL(forum, number: 19))
    XCTAssertEqual(result.path, "/forums/example.12/page-19")
    XCTAssertNil(result.fragment)
    XCTAssertEqual(URLComponents(url: result, resolvingAgainstBaseURL: false)?.queryItems,
                   [URLQueryItem(name: "prefix_id[0]", value: "23"), URLQueryItem(name: "order", value: "post_date")])
    let firstPage = try XCTUnwrap(SitePolicy.pageURL(result, number: 1))
    XCTAssertEqual(URLComponents(url: firstPage, resolvingAgainstBaseURL: false)?.path, "/forums/example.12/")
    let watched = URL(string: "https://simpcity.cr/watched/threads/?page=3")!
    XCTAssertEqual(SitePolicy.pageURL(watched, number: 9)?.query, "page=9")
    XCTAssertNil(SitePolicy.pageURL(watched, number: 1)?.query)
    XCTAssertNil(SitePolicy.pageURL(watched, number: 0))
    XCTAssertNil(SitePolicy.pageURL(watched, number: 100_000))
    XCTAssertNil(SitePolicy.pageURL(URL(string: "https://example.com/threads/a.1/")!, number: 2))
  }
  func testCompactPaginationProvidesFullSelectionRange() throws {
    let html = #"<html data-template="forum_view"><h1 class="p-title-value">Example</h1><a class="pageNavSimple-el--current" data-last="321">Page 7</a></html>"#
    let result = try ForumParser().parse(html, url: URL(string: "https://simpcity.cr/forums/example.12/page-7?prefix_id=23")!)
    XCTAssertEqual(result.pageNumber, 7)
    XCTAssertEqual(result.pageCount, 321)
    XCTAssertEqual(result.url(forPage: 320)?.path, "/forums/example.12/page-320")
    XCTAssertEqual(result.url(forPage: 320)?.query, "prefix_id=23")
    XCTAssertNil(result.url(forPage: 322))
  }
  func testLRUEvictionPreservesRecentlyReturnedPagesAndPosition() {
    let cache = PageCache(countLimit: 2, costLimit: 100)
    cache.store(page(1), cost: 30)
    cache.savePosition("post-8", for: page(1).url)
    cache.store(page(2), cost: 30)
    let anchored = URL(string: "https://simpcity.cr/threads/example.42/?page=1#post-10")!
    XCTAssertEqual(cache.value(for: anchored)?.page.url.fragment, "post-10")
    XCTAssertEqual(cache.value(for: anchored)?.visibleID, "post-8")
    cache.store(page(3), cost: 30)
    XCTAssertNil(cache.value(for: page(2).url))
    XCTAssertNotNil(cache.value(for: page(1).url))
    XCTAssertEqual(cache.count, 2)
    XCTAssertEqual(cache.totalCost, 60)
  }
  func testBudgetRefreshAndSessionInvalidation() {
    let cache = PageCache(countLimit: 20, costLimit: 100)
    cache.store(page(1), cost: 60)
    cache.store(page(2), cost: 60)
    XCTAssertNil(cache.value(for: page(1).url))
    cache.savePosition("post-55", for: page(2).url)
    cache.store(page(2, title: "Refreshed"), cost: 40)
    XCTAssertEqual(cache.value(for: page(2).url)?.page.title, "Refreshed")
    XCTAssertEqual(cache.value(for: page(2).url)?.visibleID, "post-55")
    XCTAssertEqual(cache.totalCost, 40)
    cache.store(page(3), cost: 101)
    XCTAssertNil(cache.value(for: page(3).url))
    cache.removeAll()
    XCTAssertEqual(cache.count, 0)
    XCTAssertEqual(cache.totalCost, 0)
    XCTAssertNil(cache.value(for: page(2).url))
  }
  func testCacheSeparatesFiltersButCanonicalizesQueryOrderAndFragments() throws {
    let first = URL(string: "https://simpcity.cr/forums/example.12/?prefix_id=2&order=post_date")!
    let alias = URL(string: "https://simpcity.cr/forums/example.12/page-1?order=post_date&prefix_id=2#item")!
    let other = URL(string: "https://simpcity.cr/forums/example.12/?prefix_id=3&order=post_date")!
    XCTAssertEqual(SitePolicy.pageCacheKey(first), SitePolicy.pageCacheKey(alias))
    XCTAssertNotEqual(SitePolicy.pageCacheKey(first), SitePolicy.pageCacheKey(other))
    var snapshot = page(1)
    snapshot.url = first
    let cache = PageCache()
    cache.store(snapshot)
    XCTAssertNotNil(cache.value(for: alias))
    XCTAssertNil(cache.value(for: other))
  }
}
