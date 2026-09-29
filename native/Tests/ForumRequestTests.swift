import Foundation
import XCTest
@testable import ForumCore

final class ForumRequestTests: XCTestCase {
  private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"

  private func cookie(_ name: String, domain: String = ".south-plus.net", path: String = "/", expires: Date? = nil) throws -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "synthetic", .domain: domain, .path: path, .secure: "TRUE"]
    if let expires { properties[.expires] = expires }
    return try XCTUnwrap(HTTPCookie(properties: properties))
  }

  func testReaderUsesExactBrowserIdentityOnInitialLoadAndPagination() throws {
    let loginCookie = try cookie("fixture_winduser")
    let first = try ForumRequest.page(site: .south, url: SouthSitePolicy.start, userAgent: userAgent, cookies: [loginCookie])
    let nextURL = try XCTUnwrap(SouthSitePolicy.pageURL(SouthSitePolicy.start, number: 2))
    let next = try ForumRequest.page(site: .south, url: nextURL, userAgent: userAgent, cookies: [loginCookie])
    for request in [first, next] {
      XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), userAgent)
      XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("fixture_winduser=synthetic") == true)
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertFalse(request.httpShouldHandleCookies)
      XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
    }
  }

  func testReaderDoesNotSendOtherForumExpiredOrWrongPathCookies() throws {
    let cookies = try [cookie("own"), cookie("foreign", domain: ".simpcity.cr"),
                       cookie("wrong_path", path: "/private"), cookie("expired", expires: .distantPast)]
    let request = try ForumRequest.page(site: .south, url: SouthSitePolicy.start, userAgent: userAgent, cookies: cookies)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "own=synthetic")
  }

  func testGuestRequestHasNoStaleCookieOrFragment() throws {
    let url = try XCTUnwrap(URL(string: "https://south-plus.net/read.php?tid=20#post_10"))
    let request = try ForumRequest.page(site: .south, url: url, userAgent: userAgent, cookies: [])
    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    XCTAssertNil(request.url?.fragment)
  }

  func testRequestRefusesMissingIdentityActionsAndForeignOrigins() {
    XCTAssertThrowsError(try ForumRequest.page(site: .south, url: SouthSitePolicy.start, userAgent: "", cookies: []))
    XCTAssertThrowsError(try ForumRequest.page(site: .south, url: SouthSitePolicy.login, userAgent: userAgent, cookies: []))
    XCTAssertThrowsError(try ForumRequest.page(site: .south, url: SimpSitePolicy.base, userAgent: userAgent, cookies: []))
  }
}
