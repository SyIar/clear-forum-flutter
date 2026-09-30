import Foundation
import XCTest
@testable import ForumCore

final class HostedFilesTests: XCTestCase {
  private let album = URL(string: "https://bunkr.cr/a/sampleAlbum")!
  private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
  private func albumHTML(_ objects: String) -> String { "<h1>Nature demos</h1><script>window.albumFiles.forEach(render); window.albumFiles = [\(objects)];</script>" }
  private func object(_ id: Int) -> String { "{id: \(id), original: \"Nature \(id).mp4\", slug: \"sample\(id)\", size: 12345, type: \"video\"}" }

  func testBunkrAliasesShareOneIdentityButImpersonatorsDoNotMatch() {
    for host in ["bunkr.cr", "www.bunkr.media", "bunkr.fi", "bunkrr.su", "bunkr.cloud"] {
      let url = URL(string: "https://\(host)/a/sampleAlbum")!
      XCTAssertEqual(HostedFilePolicy.provider(url), .bunkr)
      XCTAssertEqual(HostedFilePolicy.key(url), HostedFilePolicy.key(album))
    }
    for address in ["http://bunkr.cr/a/sample", "https://bunkr.cr.evil.com/a/sample", "https://bunkr.local/a/sample", "https://bunkr.cr:444/a/sample", "https://user:pass@bunkr.cr/a/sample", "https://bunkr.cr/a/a%2Fb"] {
      XCTAssertNil(HostedFilePolicy.provider(URL(string: address)!), address)
    }
  }
  func testOtherProvidersAreRecognizedByHostAndRoute() {
    XCTAssertEqual(HostedFilePolicy.provider(URL(string: "https://pixeldrain.com/l/demo")!), .pixeldrain)
    XCTAssertEqual(HostedFilePolicy.provider(URL(string: "https://pixeldrain.com/u/demo")!), .pixeldrain)
    XCTAssertEqual(HostedFilePolicy.provider(URL(string: "https://filester.me/d/demo")!), .filester)
    XCTAssertEqual(HostedFilePolicy.provider(URL(string: "https://fileditchfiles.st/folder/demo.mp4")!), .fileditch)
    XCTAssertNil(HostedFilePolicy.provider(URL(string: "https://pixeldrain.com/api/file/demo")!))
    XCTAssertNil(HostedFilePolicy.provider(URL(string: "https://filester.me.evil.com/d/demo")!))
  }
  func testSuffixAliasesDeduplicateWithoutMatchingEmbeddedBrandNames() {
    for (domain, path, host) in [("filester", "d/demo", FileHost.filester), ("pixeldrain", "u/demo", .pixeldrain), ("fileditchfiles", "folder/demo.mp4", .fileditch)] {
      let primary = URL(string: "https://\(domain).me/\(path)")!
      for suffix in ["me", "si", "sh", "gg", "net", "tech"] {
        let url = URL(string: "https://www.\(domain).\(suffix)/\(path)")!
        XCTAssertEqual(HostedFilePolicy.provider(url), host)
        XCTAssertEqual(HostedFilePolicy.key(url), HostedFilePolicy.key(primary))
      }
      for bad in ["\(domain).si.evil.com", "evil-\(domain).si", "evil.\(domain).si", "\(domain).local", "\(domain).123", "www.app.\(domain).si"] {
        XCTAssertNil(HostedFilePolicy.provider(URL(string: "https://\(bad)/\(path)")!))
      }
    }
    XCTAssertEqual(HostedFilePolicy.provider(URL(string: "https://pixeldra.in/l/demo")!), .pixeldrain)
    XCTAssertNil(HostedFilePolicy.provider(URL(string: "https://fileditchfiles.me/api/folder/demo.mp4")!))
  }
  func testMirrorRedirectsStayWithinProviderAndFilePath() {
    let original = URL(string: "https://filester.si/v2/api/public/view")!
    XCTAssertTrue(HostedFilePolicy.acceptsMetadataRedirect(from: original, to: URL(string: "https://filester.gg/v2/api/public/view")!, provider: .filester))
    for bad in ["https://filester.si.evil.com/v2/api/public/view", "https://pixeldrain.com/api/file/demo", "http://filester.me/v2/api/public/view"] {
      XCTAssertFalse(HostedFilePolicy.acceptsMetadataRedirect(from: original, to: URL(string: bad)!, provider: .filester))
    }
    let request = HostedFileRequest(url: URL(string: "https://fileditchfiles.me/folder/demo.mp4")!, referer: original, name: "demo.mp4")
    XCTAssertTrue(request.accepts(URL(string: "https://fileditchfiles.st/folder/demo.mp4")!))
    XCTAssertFalse(request.accepts(URL(string: "https://fileditchfiles.st/folder/other.mp4")!))
    XCTAssertFalse(request.accepts(URL(string: "https://fileditchfiles.st.evil.com/folder/demo.mp4")!))
  }
  func testBunkrReadsCompleteArrayBeyondVisibleCards() throws {
    let html = "<a href='/f/sample1'>One visible card</a>" + albumHTML((1...151).map(object).joined(separator: ",\n"))
    let result = try HostedFileParser.bunkrAlbum(html, url: album)
    XCTAssertEqual(result.entries.count, 151)
    XCTAssertEqual(result.entries.last?.remoteID, "151")
    XCTAssertEqual(result.entries.first?.size, 12345)
  }
  func testBunkrDoesNotSilentlyReturnPartialListWhenOneRecordIsMalformed() {
    XCTAssertThrowsError(try HostedFileParser.bunkrAlbum(albumHTML(object(1) + ", {slug: \"missing-id\"}"), url: album))
    XCTAssertThrowsError(try HostedFileParser.bunkrAlbum("<script>window.albumFiles.forEach(render)</script>", url: album))
  }
  func testBunkrFilenameCannotBecomeAnotherRecordField() throws {
    let object = #"{original: "Nature ], id: 999, }.mp4", id: 7, slug: "actual", size: 10}"#
    let result = try HostedFileParser.bunkrAlbum(albumHTML(object), url: album)
    XCTAssertEqual(result.entries.first?.remoteID, "7")
    XCTAssertEqual(result.entries.first?.name, "Nature ], id: 999, }.mp4")
  }
  func testBunkrFileUsesAlbumHeadingNotRelatedPreviewCards() throws {
    let page = URL(string: "https://bunkr.media/f/sample1")!
    let html = "<h1>Nature.mp4</h1><script data-file-id='101'></script><h2>More files in this <a href='../a/sampleAlbum'>album</a></h2><a href='../f/sample2'>Preview</a>"
    let (file, parent) = try HostedFileParser.bunkrFile(html, url: page)
    XCTAssertEqual(file.remoteID, "101")
    XCTAssertEqual(parent?.absoluteString, "https://bunkr.media/a/sampleAlbum")
  }
  func testPixeldrainListPreservesTorrentTypeAndDoesNotInventMediaURL() throws {
    let data = try json(["title": "Open source demos", "files": [
      ["id": "demo1", "name": "nature.mp4", "size": 123, "mime_type": "video/mp4"],
      ["id": "demo2", "name": "example.torrent", "size": 456, "mime_type": "application/x-bittorrent"]]])
    let result = try HostedFileParser.pixeldrain(data, url: URL(string: "https://pixeldrain.com/l/demoList")!)
    XCTAssertEqual(result.entries.count, 2)
    XCTAssertEqual(result.entries[0].pageURL.absoluteString, "https://pixeldrain.com/u/demo1")
    XCTAssertTrue(TorrentMetadata.isTorrent(name: result.entries[1].name, mime: result.entries[1].mime))
    XCTAssertThrowsError(try HostedFileParser.pixeldrain(json(["success": false, "value": "not_found"]), url: result.url))
  }
  func testFilesterCardsUseDataAttributesWithoutExecutingOnclick() throws {
    let html = """
    <h1>Open demos</h1><a href='/f/parent'>Parent</a>
    <div id='filesGrid'><div class='file-item' data-name='Sample.mp4' data-size='1048576' onclick="window.location.href='/d/sample1'"></div></div>
    <div id='subfoldersGrid'><a class='subfolder-item' href='/f/child'><span class='folder-name'>More</span></a></div>
    <button id='loadAllPagesBtn' data-total='3'>Load all</button>
    """
    let result = try HostedFileParser.filester(html, url: URL(string: "https://filester.me/f/root")!)
    XCTAssertEqual(result.pages, 3)
    XCTAssertEqual(result.entries.count, 2)
    XCTAssertEqual(result.entries[0].name, "Sample.mp4")
    XCTAssertEqual(result.entries[0].size, 1048576)
    XCTAssertTrue(result.entries[1].folder)
  }
  func testFilesterTokenIsEscapedAndUntrustedServerRejected() throws {
    let entry = HostedFileEntry(pageURL: URL(string: "https://filester.me/d/demo")!, name: "Nature.mp4")
    let data = try json(["file": "file-uuid", "token": "a&b+c", "server": "https://cn1.filester.me"])
    let result = try HostedFileParser.filesterDownload(data, entry: entry)
    let query = URLComponents(url: result.url, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(query.first(where: { $0.name == "token" })?.value, "a&b+c")
    XCTAssertEqual(query.first(where: { $0.name == "download" })?.value, "true")
    XCTAssertThrowsError(try HostedFileParser.filesterDownload(json(["file": "id", "token": "t", "server": "https://filester.me.evil.com"]), entry: entry))
    XCTAssertNoThrow(try HostedFileParser.filesterDownload(json(["file": "id", "token": "t"]), entry: entry))
    XCTAssertNoThrow(try HostedFileParser.filesterDownload(json(["file": "id", "token": "t", "server": "https://cn1.filester.si"]), entry: entry))
    XCTAssertThrowsError(try HostedFileParser.filesterDownload(json(["file": "id", "token": "t", "server": "https://cdn.notfilester.si"]), entry: entry))
  }
  func testFilesterRoundedSizeIsDisplayOnlyNotTransferValidation() throws {
    let html = "<h1 id='fileTitle'>Nature.mp4</h1><div id='detailsContent'><div><span>Size</span><span>4.51 MB</span></div></div>"
    let listing = try HostedFileParser.filester(html, url: URL(string: "https://filester.si/d/demo")!)
    let entry = try XCTUnwrap(listing.entries.first)
    XCTAssertEqual(entry.sizeDescription, "4.51 MB")
    XCTAssertNil(entry.size)
    let request = try HostedFileParser.filesterDownload(json(["file": "id", "token": "t"]), entry: entry)
    XCTAssertNil(request.size)
    let noSize = try HostedFileParser.filester("<h1 id='fileTitle'>demo.zip</h1>", url: listing.url)
    XCTAssertEqual(noSize.entries.first?.sizeDescription, "Size unknown")
  }
  func testFileditchStatusDistinguishesExactSizeMissingAndUnknown() throws {
    XCTAssertEqual(try HostedFileParser.fileditchSize(json(["status": true, "size": 50720388])), 50720388)
    XCTAssertNil(try HostedFileParser.fileditchSize(json(["status": "unknown", "size": NSNull()])))
    XCTAssertThrowsError(try HostedFileParser.fileditchSize(json(["status": false, "size": NSNull()])))
    XCTAssertThrowsError(try HostedFileParser.fileditchSize(json(["status": true, "size": -1])))
  }
  func testBunkrCurrentPublicResponseDecodingAndMaintenanceRejection() throws {
    let entry = HostedFileEntry(pageURL: URL(string: "https://bunkr.cr/f/demo")!, name: "Nature.mp4", remoteID: "101")
    let address = "https://cdn.example.com/Nature.mp4"
    let key = Array("SECRET_KEY_2".utf8)
    let encoded = Data(address.utf8.enumerated().map { $0.element ^ key[$0.offset % key.count] }).base64EncodedString()
    let result = try HostedFileParser.bunkrDownload(json(["url": encoded, "encrypted": true, "timestamp": 7201]), entry: entry)
    XCTAssertEqual(result.url.absoluteString, address)
    XCTAssertFalse(result.accepts(URL(string: "https://other.example.com/Nature.mp4")!))
    XCTAssertThrowsError(try HostedFileParser.bunkrDownload(json(["url": "https://cdn.example.com/maint.mp4"]), entry: entry))
    XCTAssertThrowsError(try HostedFileParser.bunkrDownload(json(["url": "https://127.0.0.1/demo.mp4"]), entry: entry))
  }
  func testBatchDeduplicatesAliasesPreservesOrderAndPreventsFilenameCollisions() throws {
    let one = HostedFileEntry(pageURL: URL(string: "https://bunkr.cr/f/one")!, name: "Sample.mp4")
    let alias = HostedFileEntry(pageURL: URL(string: "https://bunkr.media/f/one")!, name: "Duplicate.mp4")
    let two = HostedFileEntry(pageURL: URL(string: "https://bunkr.cr/f/two")!, name: "sample.mp4")
    let unsafe = HostedFileEntry(pageURL: URL(string: "https://bunkr.cr/f/three")!, name: "../escape.mp4")
    var plan = try HostedBatchPlan(HostedFileListing(url: album, title: "Demos", entries: [one, alias, two, unsafe]))
    XCTAssertEqual(plan.pending.map { $0.entry.id }, [one.id, two.id, unsafe.id])
    XCTAssertEqual(plan.pending[1].path, ["sample (2).mp4"])
    XCTAssertFalse(plan.pending[2].path[0].contains("/"))
    plan.advance(); XCTAssertEqual(plan.pending.first?.entry.id, two.id)
  }
  func testFolderCyclesCannotEnqueueRootAgain() throws {
    let root = URL(string: "https://filester.me/f/root")!, child = URL(string: "https://filester.me/f/child")!
    var plan = try HostedBatchPlan(HostedFileListing(url: root, title: "Root", entries: [HostedFileEntry(pageURL: child, name: "Child", folder: true)]))
    try plan.expand(HostedFileListing(url: child, title: "Child", entries: [HostedFileEntry(pageURL: root, name: "Root", folder: true)]))
    XCTAssertTrue(plan.pending.isEmpty)
  }
  func testDownloadedWebPageAndPartialResponseAreNotSavedAsVideo() {
    let html = Data("<!doctype html><html>Access denied</html>".utf8)
    XCTAssertNotNil(HostedFilePolicy.responseError(status: 200, mime: "application/octet-stream", bytes: 3072, expected: nil, prefix: html))
    XCTAssertNotNil(HostedFilePolicy.responseError(status: 206, mime: "video/mp4", bytes: 10, expected: 10, prefix: Data()))
    XCTAssertNotNil(HostedFilePolicy.responseError(status: 200, mime: "video/mp4", bytes: 9, expected: 10, prefix: Data()))
    XCTAssertNil(HostedFilePolicy.responseError(status: 200, mime: "text/plain", bytes: 3, expected: 3, prefix: Data("abc".utf8)))
  }
  @MainActor
  func testClientExpandsFileToCompleteAlbumWithoutResolvingAnyDownloads() async throws {
    var paths: [String] = []
    let client = HostedFileClient { url, _, body, _ in
      paths.append(url.path); XCTAssertNil(body)
      if url.path.hasPrefix("/f/") { return Data("<h1>Nature.mp4</h1><div data-file-id='1'></div><h2><a href='../a/sampleAlbum'>album</a></h2>".utf8) }
      XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "1")
      return Data(self.albumHTML(self.object(1) + "," + self.object(2)).utf8)
    }
    let listing = try await client.listing(URL(string: "https://bunkr.media/f/sample1")!)
    XCTAssertTrue(listing.expandedAlbum)
    XCTAssertEqual(listing.entries.count, 2)
    XCTAssertEqual(paths, ["/f/sample1", "/a/sampleAlbum"])
  }
  @MainActor
  func testMirrorMetadataAndResolutionKeepSelectedOrigin() async throws {
    let client = HostedFileClient { url, host, body, referer in
      if host == .filester {
        XCTAssertEqual(url.absoluteString, "https://filester.si/v2/api/public/download")
        XCTAssertEqual(referer?.host, "filester.si")
        XCTAssertEqual(body?["file_slug"], "demo")
        return try self.json(["file": "file-id", "token": "demo"])
      }
      XCTAssertEqual(url.absoluteString, "https://pixeldrain.net/api/list/demo")
      return try self.json(["title": "Demos", "files": [["id": "one", "name": "demo.txt", "size": 100]]])
    }
    _ = try await client.resolve(HostedFileEntry(pageURL: URL(string: "https://filester.si/d/demo")!, name: "demo.txt"))
    let list = try await client.listing(URL(string: "https://pixeldrain.net/l/demo")!)
    let entry = try XCTUnwrap(list.entries.first)
    XCTAssertEqual(entry.pageURL.absoluteString, "https://pixeldrain.net/u/one")
    let request = try await client.resolve(entry)
    XCTAssertEqual(request.url.absoluteString, "https://pixeldrain.net/api/file/one?download")
  }
  @MainActor
  func testFileditchReadsSizeFromStatusWithoutFetchingFileBody() async throws {
    var requests = 0
    let client = HostedFileClient { url, host, body, _ in
      requests += 1
      XCTAssertEqual(host, .fileditch)
      XCTAssertNil(body)
      XCTAssertEqual(url.absoluteString, "https://fileditchfiles.me/api/folder/demo%20file+1.zip")
      return try self.json(["status": true, "size": 123456])
    }
    let listing = try await client.listing(URL(string: "https://fileditchfiles.me/folder/demo%20file+1.zip#preview")!)
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(listing.entries.first?.size, 123456)
  }
  @MainActor
  func testUnavailableFileditchSizeDoesNotHideDownloadableEntry() async throws {
    let client = HostedFileClient { _, _, _, _ in throw HostedFileFailure.format }
    let listing = try await client.listing(URL(string: "https://fileditchfiles.st/folder/demo.zip")!)
    XCTAssertEqual(listing.entries.count, 1)
    XCTAssertEqual(listing.entries.first?.sizeDescription, "Size unknown")
  }
  @MainActor
  func testClientLoadsEveryFilesterPageBeforeReturning() async throws {
    var pages: [String] = []
    let client = HostedFileClient { url, _, _, _ in
      XCTAssertEqual(url.host, "filester.si")
      let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? "1"
      pages.append(page)
      return Data("<h1>Demos</h1><div id='filesGrid'><div class='file-item' data-name='Sample.mp4' onclick=\"window.location.href='/d/file\(page)'\"></div></div><button id='loadAllPagesBtn' data-total='2'></button>".utf8)
    }
    let listing = try await client.listing(URL(string: "https://filester.si/f/demo?page=2")!)
    XCTAssertEqual(pages, ["1", "2"])
    XCTAssertEqual(listing.entries.count, 2)
  }
}
