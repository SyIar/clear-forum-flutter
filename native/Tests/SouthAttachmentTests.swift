import XCTest
@testable import ForumCore

final class SouthAttachmentTests: XCTestCase {
  private let legacy = URL(string: "https://south-plus.net/job.php?action-download-pid-901-tid-20-aid-81.html")!
  private let query = URL(string: "https://south-plus.net/job.php?aid=81&tid=20&pid=901&action=download")!

  func testEquivalentURLsIdentifyTheSameQueuedFile() throws {
    let attachment = try XCTUnwrap(SouthAttachment(url: legacy))
    XCTAssertEqual(attachment, SouthAttachment(url: query))
    XCTAssertEqual(attachment.attachmentID, "81")
    XCTAssertEqual(attachment.page.absoluteString, "https://south-plus.net/read.php?tid=20#901")
    XCTAssertEqual(HostedFilePolicy.key(legacy), HostedFilePolicy.key(query))
    let listing = HostedFileListing(url: legacy, title: "Archive.zip", entries: [
      HostedFileEntry(pageURL: legacy, name: "Archive.zip"), HostedFileEntry(pageURL: query, name: "Archive.zip")
    ])
    let plan = try HostedBatchPlan(listing)
    let restored = try JSONDecoder().decode(HostedBatchPlan.self, from: JSONEncoder().encode(plan))
    XCTAssertEqual(restored.pending.count, 1)
    XCTAssertEqual(restored.pending.first?.path, ["Archive.zip"])
    XCTAssertNil(HostedFilePolicy.provider(legacy), "Forum login must stay out of public file-host resolvers")
  }
  func testOnlyAttachmentDownloadActionsAreRecognized() {
    for value in [
      "https://south-plus.net/job.php?action=buytopic&pid=901&tid=20&aid=81",
      "https://south-plus.net/job.php?action=download&pid=901&tid=20&aid=81&verify=token",
      "https://south-plus.net/job.php?action=download&pid=901&tid=20&aid=81&aid=82",
      "https://south-plus.net/job.php?action=download&tid=20&aid=81",
      "https://south-plus.net/job.php?action-download-pid-901-tid-20-aid-0.html",
      "https://south-plus.net/job.php?action-download-pid-901-tid-20-aid-81-extra-x.html",
      "https://south-plus.net/job.php?action-download-pid-901-tid-20-aid-81.html%0A",
      "https://south-plus.net/read.php?action=download&pid=901&tid=20&aid=81",
      "https://south-plus.net.example.com/job.php?action=download&pid=901&tid=20&aid=81",
      "https://south-plus.net:8443/job.php?action=download&pid=901&tid=20&aid=81",
      "https://user:pass@south-plus.net/job.php?action=download&pid=901&tid=20&aid=81",
      "http://south-plus.net/job.php?action=download&pid=901&tid=20&aid=81"
    ] { XCTAssertNil(SouthAttachment(url: URL(string: value)!), value) }
  }
  func testRedirectsRemainInAttachmentEndpoints() {
    let request = HostedFileRequest(url: legacy, referer: SouthSitePolicy.base, name: "Archive.zip")
    XCTAssertTrue(request.accepts(query))
    XCTAssertTrue(request.accepts(URL(string: "https://south-plus.net/attachment/Mon_2609/archive.zip")!))
    for value in [
      "https://south-plus.net/job.php?action-download-pid-901-tid-20-aid-82.html",
      "https://south-plus.net/login.php",
      "https://south-plus.net/job.php?action=buytopic&tid=20&pid=901&verify=token",
      "https://south-plus.net/attachment/../login.php",
      "https://south-plus.net/attachment/",
      "http://south-plus.net/attachment/archive.zip",
      "https://cdn.example.com/attachment/archive.zip",
      "https://south-plus.net.example.com/attachment/archive.zip"
    ] { XCTAssertFalse(request.accepts(URL(string: value)!), value) }
  }
  func testCookiesAreScopedBySitePathAndExpiry() throws {
    func cookie(_ domain: String, path: String = "/", expires: Date = Date().addingTimeInterval(600)) throws -> HTTPCookie {
      try XCTUnwrap(HTTPCookie(properties: [.domain: domain, .path: path, .name: "auth", .value: "synthetic", .expires: expires]))
    }
    XCTAssertTrue(SouthSitePolicy.matches(try cookie(".south-plus.net"), url: legacy))
    XCTAssertFalse(SouthSitePolicy.matches(try cookie("simpcity.cr"), url: legacy))
    XCTAssertFalse(SouthSitePolicy.matches(try cookie("south-plus.net", path: "/read.php"), url: legacy))
    XCTAssertFalse(SouthSitePolicy.matches(try cookie("south-plus.net", expires: .distantPast), url: legacy))
    XCTAssertFalse(SouthSitePolicy.matches(try cookie("south-plus.net"), url: URL(string: "https://cdn.example.com/file.zip")!))
  }
  func testHTMLLoginAndPermissionPagesCannotBecomeSavedArchives() {
    for mime in ["text/html", "application/octet-stream"] {
      XCTAssertNotNil(HostedFilePolicy.responseError(status: 200, mime: mime, bytes: 3072, expected: nil,
                                                    prefix: Data("<!DOCTYPE html><html>Login required</html>".utf8)))
    }
    XCTAssertNil(HostedFilePolicy.responseError(status: 200, mime: "application/zip", bytes: 4096, expected: nil,
                                              prefix: Data([0x50, 0x4b, 0x03, 0x04])))
  }
}
