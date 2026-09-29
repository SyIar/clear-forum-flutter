import Foundation
import SwiftSoup
import XCTest
@testable import ForumCore

final class MediaFilePolicyTests: XCTestCase {
  func testIncompleteAndNonMediaResponsesCannotBeSavedAsVideo() {
    let url = URL(string: "https://media.example/file.mp4")!
    for status in [206, 301, 401, 403, 404, 500] {
      XCTAssertNotNil(MediaFilePolicy.responseError(status: status, mime: "video/mp4", url: url, bytes: 1024, limit: 4096))
    }
    for mime in ["text/html", "application/xhtml+xml", "application/json"] {
      XCTAssertNotNil(MediaFilePolicy.responseError(status: 200, mime: mime, url: url, bytes: 1024, limit: 4096))
    }
    XCTAssertNotNil(MediaFilePolicy.responseError(status: 200, mime: "video/mp4", url: url, bytes: 0, limit: 4096))
    XCTAssertNotNil(MediaFilePolicy.responseError(status: 200, mime: "video/mp4", url: url, bytes: 4097, limit: 4096))
    XCTAssertNil(MediaFilePolicy.responseError(status: 200, mime: "video/mp4", url: url, bytes: 4096, limit: 4096))
  }
  func testHLSIsIdentifiedByPathOrResponseNotSignedQuery() {
    let playlist = URL(string: "https://media.example/index.M3U8?signature=example")!
    let opaque = URL(string: "https://media.example/stream?format=mp4")!
    XCTAssertTrue(MediaFilePolicy.isHLS(playlist, mime: "application/octet-stream"))
    XCTAssertTrue(MediaFilePolicy.isHLS(opaque, mime: "Application/Vnd.Apple.Mpegurl"))
    XCTAssertNotNil(MediaFilePolicy.responseError(status: 200, mime: "application/x-mpegurl", url: opaque, bytes: 1024, limit: 4096))
    XCTAssertFalse(MediaFilePolicy.isHLS(URL(string: "https://media.example/clip.mp4?name=index.m3u8")!, mime: "video/mp4"))
  }
  func testExplicitImageOriginalAndSafeFallback() throws {
    let page = URL(string: "https://simpcity.cr/threads/example.1/")!
    let preview = URL(string: "https://images.example/preview.jpg")!
    let node = try XCTUnwrap(try SwiftSoup.parse(#"<img data-original="https://images.example/original.png">"#).select("img").first())
    XCTAssertEqual(OriginalImageSource.resolve(node, page: page, preview: preview, link: nil).lastPathComponent, "original.png")
    try node.attr("data-original", "javascript:invalid()")
    XCTAssertEqual(OriginalImageSource.resolve(node, page: page, preview: preview, link: URL(string: "https://images.example/view/12")), preview)
    XCTAssertEqual(OriginalImageSource.resolve(node, page: page, preview: preview, link: URL(string: "https://images.example/full.JPG?token=example")).path, "/full.JPG")
  }
  func testBothBodyParsersPreserveSourceAndPreviewSeparately() throws {
    let root = try SwiftSoup.parse(#"<a href="https://images.example/full.png"><img src="https://images.example/thumb.jpg"></a>"#)
    let page = URL(string: "https://simpcity.cr/threads/example.1/")!
    let simp = try SimpForumParser().parseBody(root, page: page)
    let south = try SouthBodyParser().parseBody(root, page: URL(string: "https://south-plus.net/read.php?tid-1.html")!)
    for blocks in [simp, south] {
      let image = try XCTUnwrap(blocks.first { $0.kind == .image })
      XCTAssertEqual(image.url?.lastPathComponent, "thumb.jpg")
      XCTAssertEqual(image.original?.lastPathComponent, "full.png")
    }
  }
}
