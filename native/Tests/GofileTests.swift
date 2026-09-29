import Foundation
import XCTest
@testable import ForumCore

final class GofileTests: XCTestCase {
  private let page = URL(string: "https://gofile.io/d/test-folder")!
  private let file = URL(string: "https://store5.gofile.io/download/web/file-1/photo.png")!
  func testRecognizesShareAndDirectFilesWithoutAcceptingImpersonatingHosts() {
    XCTAssertEqual(GofilePolicy.pageURL(URL(string: "http://www.gofile.io/d/abc123?tracking=1")!)?.absoluteString, "https://gofile.io/d/abc123")
    XCTAssertEqual(GofilePolicy.pageURL(file)?.absoluteString, "https://gofile.io/d/file-1")
    for value in ["https://gofile.io.evil.test/d/abc", "https://evil.test/gofile.io/d/abc", "https://user:pass@gofile.io/d/abc", "https://gofile.io/d/abc/extra", "https://gofile.io/d/a%2Fb", "file:///d/abc"] {
      XCTAssertNil(GofilePolicy.pageURL(URL(string: value)!), value)
    }
  }
  func testRejectsHTMLPageSavedAsThreeKilobyteImage() {
    let html = Data("<!doctype html><html><title>Gofile</title></html>".utf8)
    XCTAssertNotNil(GofilePolicy.responseError(status: 200, url: file, mime: "text/html", expectedMIME: "image/png", bytes: 3358, expectedBytes: 70932, prefix: html))
    XCTAssertNotNil(GofilePolicy.responseError(status: 200, url: file, mime: "application/octet-stream", expectedMIME: "image/png", bytes: 3358, expectedBytes: nil, prefix: html))
    XCTAssertNotNil(GofilePolicy.responseError(status: 200, url: page, mime: "text/html", expectedMIME: "image/png", bytes: 3358, expectedBytes: nil, prefix: html))
  }
  func testValidSmallFilesAreNotRejectedJustForTheirSize() {
    XCTAssertNil(GofilePolicy.responseError(status: 200, url: file, mime: "text/plain", expectedMIME: "text/plain", bytes: 3, expectedBytes: 3, prefix: Data("abc".utf8)))
    XCTAssertNil(GofilePolicy.responseError(status: 200, url: file, mime: "text/html", expectedMIME: "text/html", bytes: 6, expectedBytes: 6, prefix: Data("<html>".utf8)))
    XCTAssertNil(GofilePolicy.responseError(status: 200, url: file, mime: "application/octet-stream", expectedMIME: "", bytes: 0, expectedBytes: 0, prefix: Data()))
  }
  func testPartialAndMismatchedDownloadsFail() {
    XCTAssertNotNil(GofilePolicy.responseError(status: 206, url: file, mime: "image/png", expectedMIME: "image/png", bytes: 10, expectedBytes: 10, prefix: Data()))
    XCTAssertNotNil(GofilePolicy.responseError(status: 200, url: file, mime: "image/png", expectedMIME: "image/png", bytes: 9, expectedBytes: 10, prefix: Data()))
    XCTAssertNotNil(GofilePolicy.responseError(status: 200, url: file, mime: "application/json", expectedMIME: "image/png", bytes: 10, expectedBytes: nil, prefix: Data()))
  }
  func testFilenameCannotEscapeTemporaryDirectory() {
    XCTAssertEqual(GofilePolicy.filename("../a\\b:photo.png"), ".._a_b_photo.png")
    XCTAssertEqual(GofilePolicy.filename(".."), "Download")
    XCTAssertEqual(GofilePolicy.filename(" \n"), "_")
  }
  private func payload() -> [String: Any] {
    ["contentId": "test-folder", "page": 1, "status": "ok", "totalPages": 2, "data": ["name": "Test folder", "type": "folder", "canAccess": true, "children": [
      ["id": "file-1", "name": "photo.png", "type": "file", "size": 70932, "mimetype": "image/png", "link": file.absoluteString],
      ["id": "folder-2", "name": "More", "type": "folder"],
      ["id": "blocked-3", "name": "Unavailable", "type": "file", "isFrozen": true]
    ]]]
  }
  func testFolderMetadataAndAvailability() throws {
    let value = try GofileListing.parse(payload(), requested: page, page: 1)
    XCTAssertEqual(value.title, "Test folder")
    XCTAssertEqual(value.pages, 2)
    XCTAssertEqual(value.entries.count, 3)
    XCTAssertEqual(value.entries[0].link, file)
    XCTAssertEqual(value.entries[0].size, 70932)
    XCTAssertTrue(value.entries[1].folder)
    XCTAssertTrue(value.entries[2].unavailable)
  }
  func testWrongFolderAndWrongPageCannotReplaceCurrentListing() {
    XCTAssertThrowsError(try GofileListing.parse(payload(), requested: page, page: 2))
    XCTAssertThrowsError(try GofileListing.parse(payload(), requested: URL(string: "https://gofile.io/d/other")!, page: 1))
  }
  func testAccessGateDoesNotBecomeAnEmptySuccessfulFolder() {
    var value = payload()
    value["data"] = ["canAccess": false, "children": []] as [String: Any]
    XCTAssertThrowsError(try GofileListing.parse(value, requested: page, page: 1))
  }
  func testForeignURLsAndDuplicateIDsAreFiltered() throws {
    var value = payload()
    value["data"] = ["type": "folder", "children": [
      ["id": "file-1", "name": "Test", "type": "file", "link": "https://attacker.test/download/web/file-1/secret", "thumbnail": "https://store5.gofile.io/download/web/other/thumb"],
      ["id": "file-1", "name": "Duplicate", "type": "file"]
    ]]
    let listing = try GofileListing.parse(value, requested: page, page: 1)
    XCTAssertEqual(listing.entries.count, 1)
    XCTAssertNil(listing.entries.first?.link)
    XCTAssertNil(listing.entries.first?.thumbnail)
  }
}
