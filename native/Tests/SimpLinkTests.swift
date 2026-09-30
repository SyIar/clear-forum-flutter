import Foundation
import XCTest
@testable import ForumCore

final class SimpLinkTests: XCTestCase {
  private let thread = URL(string: "https://simpcity.cr/threads/example.123/")!

  private func wrapper(_ address: String, padded: Bool = false) -> URL {
    let encoded = Data(address.utf8).base64EncodedString()
    var parts = URLComponents(string: "https://simpcity.cr/redirect/")!
    parts.queryItems = [URLQueryItem(name: "to", value: padded ? encoded : encoded.replacingOccurrences(of: "=", with: "")),
                        URLQueryItem(name: "e", value: "1"), URLQueryItem(name: "m", value: "b64")]
    return parts.url!
  }

  func testObservedRelativeWrapperBecomesDirectGofileLink() throws {
    let destination = URL(string: "https://gofile.io/d/SyntheticFixture")!
    let wrapped = wrapper(destination.absoluteString)
    let href = (wrapped.path + "?" + wrapped.query!).replacingOccurrences(of: "&", with: "&amp;")
    let source = """
    <html data-template="thread_view"><h1 class="p-title-value">Sample</h1>
    <article class="message--post"><div class="message-body"><div class="bbWrapper">
      <a href="\(href)" target="_blank" class="link link--external" rel="nofollow ugc noopener" data-blank-handler="true">Files</a>
    </div></div></article></html>
    """
    let page = try ForumParser().parse(source, url: thread)
    let link = try XCTUnwrap(page.posts.first?.blocks.flatMap(\.runs).first { $0.url != nil }?.url)
    XCTAssertEqual(link, destination)
    XCTAssertEqual(GofilePolicy.pageURL(link), destination)
    XCTAssertEqual(SimpSitePolicy.linkDestination(wrapper(destination.absoluteString, padded: true).absoluteString, from: thread), destination)
  }

  func testBrowserLeavesOrdinaryUnreadAndPostRequestsUnchanged() throws {
    for address in ["https://simpcity.cr/threads/example.123/unread",
                    "https://simpcity.cr/threads/example.123/unread?new=1",
                    "https://simpcity.cr/threads/example.123/post-101",
                    "https://simpcity.cr/threads/example.123/page-4#post-101"] {
      let requested = try XCTUnwrap(URL(string: address))
      XCTAssertNil(SimpSitePolicy.browserRedirectDestination(requested))
      XCTAssertEqual(SimpSitePolicy.browserRedirectDestination(requested) ?? requested, requested)
    }
    let unread = try XCTUnwrap(URL(string: "https://simpcity.cr/threads/example.123/unread?new=1"))
    XCTAssertEqual(SimpSitePolicy.resolve(unread.absoluteString, from: thread), thread,
                   "Reader normalization remains separate from browser navigation")
  }

  func testBrowserStillUnwrapsGofileAndRejectsMalformedWrappers() throws {
    let destination = try XCTUnwrap(URL(string: "https://gofile.io/d/SyntheticFixture"))
    let wrapped = wrapper(destination.absoluteString)
    XCTAssertEqual(SimpSitePolicy.browserRedirectDestination(wrapped), destination)
    XCTAssertEqual(SimpSitePolicy.browserRedirectDestination(wrapper(wrapped.absoluteString)), destination)
    let malformed = try XCTUnwrap(URL(string: wrapped.absoluteString + "&to=duplicate"))
    XCTAssertNil(SimpSitePolicy.browserRedirectDestination(malformed))
    let foreign = try XCTUnwrap(URL(string: wrapped.absoluteString.replacingOccurrences(of: "simpcity.cr", with: "other.example")))
    XCTAssertNil(SimpSitePolicy.browserRedirectDestination(foreign))
  }

  func testUnfurlLinksDecodeButAutomaticResourcesDoNot() throws {
    let destination = URL(string: "https://files.example/item?part=1&name=a%2Bb#section")!
    let wrapped = wrapper(destination.absoluteString)
    let href = wrapped.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
    let source = """
    <html data-template="thread_view"><article class="message--post"><div class="message-body"><div class="bbWrapper">
      <div class="bbCodeBlock--unfurl"><div class="js-unfurl-title"><a href="\(href)">A file</a></div></div>
      <img src="\(href)"><iframe src="\(href)"></iframe>
    </div></div></article></html>
    """
    let page = try ForumParser().parse(source, url: thread)
    let blocks = try XCTUnwrap(page.posts.first?.blocks)
    XCTAssertEqual(blocks.first { $0.kind == .link }?.url, destination)
    XCTAssertEqual(blocks.first { $0.kind == .image }?.url, wrapped)
    XCTAssertEqual(blocks.first { $0.kind == .media }?.url, wrapped)
    XCTAssertEqual(SimpSitePolicy.resolve(wrapped.absoluteString, from: thread), wrapped)
    XCTAssertFalse(SimpSitePolicy.readable(wrapped))
    XCTAssertFalse(SimpSitePolicy.readable(destination))
    XCTAssertThrowsError(try ForumRequest.page(site: .simp, url: destination, userAgent: "test", cookies: []))
    XCTAssertThrowsError(try SimpSearch.request(url: wrapped, userAgent: "test", cookies: []))
    let cookie = HTTPCookie(properties: [.name: "session", .value: "synthetic", .domain: "simpcity.cr", .path: "/", .secure: "TRUE"])!
    XCTAssertFalse(SimpSitePolicy.matches(cookie, url: destination))
  }

  func testNestedDecodingIsBoundedAndRetainsSafeForumRoutes() {
    let destination = URL(string: "https://files.example/item")!
    var nested = destination
    for _ in 0..<4 { nested = wrapper(nested.absoluteString) }
    XCTAssertEqual(SimpSitePolicy.linkDestination(nested.absoluteString, from: thread), destination)
    nested = wrapper(nested.absoluteString)
    XCTAssertNil(SimpSitePolicy.linkDestination(nested.absoluteString, from: thread))
    XCTAssertEqual(SimpSitePolicy.linkDestination(wrapper(thread.absoluteString).absoluteString, from: thread), thread)
  }

  func testUnsafePayloadsAndInvalidContractsAreRejected() {
    for address in ["javascript:alert(1)", "data:text/html,sample", "file:///tmp/example", "http://simpcity.cr/threads/example.123/",
                    "https://user:secret@files.example/item", "//files.example/item", "/threads/example.123/",
                    "https://simpcity.cr/logout/", "https://simpcity.cr/threads/example.123/?delete=1",
                    "https://files.example/item\n", "https://files.example\\@other.example/item"] {
      XCTAssertNil(SimpSitePolicy.linkDestination(wrapper(address).absoluteString, from: thread), address)
    }
    let valid = wrapper("https://files.example/item").absoluteString
    for address in [valid + "&to=duplicate", valid + "&extra=1", valid + "#fragment",
                    valid.replacingOccurrences(of: "m=b64", with: "m=other"),
                    valid.replacingOccurrences(of: "e=1", with: "e=0"),
                    "https://simpcity.cr/redirect/?to=A&e=1&m=b64",
                    "https://simpcity.cr/redirect/?to=***&e=1&m=b64",
                    "https://simpcity.cr/redirect/?to=%2F%2F8&e=1&m=b64"] {
      XCTAssertNil(SimpSitePolicy.linkDestination(address, from: thread), address)
    }
    XCTAssertNil(SimpSitePolicy.linkDestination(wrapper("https://files.example/" + String(repeating: "x", count: 9000)).absoluteString, from: thread))
  }

  func testExternalHTTPUsesOnlyTheExplicitNavigationPath() throws {
    for address in ["http://files.example/item?a=1#part", "http://files.example:8080/item", "https://files.example:8443/item"] {
      let destination = URL(string: address)!
      XCTAssertEqual(SimpSitePolicy.linkDestination(address, from: thread), destination)
      XCTAssertEqual(SimpSitePolicy.linkDestination(wrapper(address).absoluteString, from: thread), destination)
      XCTAssertFalse(SimpSitePolicy.readable(destination))
      XCTAssertThrowsError(try ForumRequest.page(site: .simp, url: destination, userAgent: "test", cookies: []))
      if destination.scheme == "http" { XCTAssertNil(SimpSitePolicy.resolve(address, from: thread)) }
    }
    for address in ["http://simpcity.cr/threads/example.123/", "http://user:secret@files.example/item", "http://files.example:65536/item"] {
      XCTAssertNil(SimpSitePolicy.linkDestination(address, from: thread))
      XCTAssertNil(SimpSitePolicy.linkDestination(wrapper(address).absoluteString, from: thread))
    }
    let source = """
    <html data-template="thread_view"><article class="message--post"><div class="message-body"><div class="bbWrapper">
      <a href="http://files.example/item">File</a><img src="http://files.example/image.jpg"><iframe src="http://files.example/embed"></iframe>
    </div></div></article></html>
    """
    let page = try ForumParser().parse(source, url: thread)
    let blocks = try XCTUnwrap(page.posts.first?.blocks)
    XCTAssertEqual(blocks.flatMap(\.runs).first { $0.url != nil }?.url?.scheme, "http")
    XCTAssertFalse(blocks.contains { $0.kind == .image })
    XCTAssertNil(blocks.first { $0.kind == .media }?.url)
  }

  func testUnrelatedRedirectorsAreNotDecoded() {
    let wrapped = wrapper("https://files.example/item")
    let foreign = URL(string: wrapped.absoluteString.replacingOccurrences(of: "simpcity.cr", with: "other.example"))!
    let unknownPath = URL(string: wrapped.absoluteString.replacingOccurrences(of: "/redirect/", with: "/other-redirect/"))!
    XCTAssertEqual(SimpSitePolicy.linkDestination(foreign.absoluteString, from: thread), foreign)
    XCTAssertEqual(SimpSitePolicy.linkDestination(unknownPath.absoluteString, from: thread), unknownPath)
    let direct = URL(string: "https://files.example/item#part")!
    XCTAssertEqual(SimpSitePolicy.linkDestination(direct.absoluteString, from: thread), direct)
  }
}
