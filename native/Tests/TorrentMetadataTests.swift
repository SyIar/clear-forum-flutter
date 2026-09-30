import Foundation
import XCTest
@testable import ForumCore

final class TorrentMetadataTests: XCTestCase {
  private let info = "d6:lengthi3e4:name8:demo.txt12:piece lengthi16384e6:pieces20:01234567890123456789e"
  func testV1UsesHashOfOriginalInfoBytes() throws {
    let torrent = try TorrentMetadata.parse(Data(("d4:info" + info + "e").utf8))
    let query = URLComponents(url: torrent.magnet, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(query.first(where: { $0.name == "xt" })?.value, "urn:btih:2bb50dc65274c0b705e8a6da89c4b6a6210bcf79")
    XCTAssertEqual(torrent.name, "demo.txt")
    XCTAssertFalse(torrent.v2Only)
  }
  func testTrackerQueryAndNameAreEncodedAsData() throws {
    let tracker = "https://tracker.example.com/announce?x=1&y=2"
    let body = "d8:announce\(tracker.utf8.count):\(tracker)4:info\(info)e"
    let result = try TorrentMetadata.parse(Data(body.utf8))
    let query = URLComponents(url: result.magnet, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(query.filter { $0.name == "tr" }.map(\.value), [tracker])
    XCTAssertEqual(query.count, 3)
  }
  func testAnnounceListDeduplicatesTrackers() throws {
    let tracker = "https://tracker.example.com/announce"
    let text = "\(tracker.utf8.count):\(tracker)"
    let data = Data("d8:announce\(text)13:announce-listll\(text)eee4:info\(info)e".utf8)
    // An extra list terminator must not be accepted as a successful torrent.
    XCTAssertThrowsError(try TorrentMetadata.parse(data))
    let valid = Data("d8:announce\(text)13:announce-listll\(text)ee4:info\(info)e".utf8)
    let result = try TorrentMetadata.parse(valid)
    XCTAssertEqual(URLComponents(url: result.magnet, resolvingAgainstBaseURL: false)!.queryItems!.filter { $0.name == "tr" }.count, 1)
  }
  func testV2DoesNotGenerateAnIncorrectV1Hash() throws {
    let info = "d9:file treede12:meta versioni2e4:name4:demo12:piece lengthi16384ee"
    let result = try TorrentMetadata.parse(Data("d4:info\(info)e".utf8))
    XCTAssertTrue(result.v2Only)
    let xt = URLComponents(url: result.magnet, resolvingAgainstBaseURL: false)!.queryItems!.first!.value
    XCTAssertEqual(xt, "urn:btmh:122064e96f3aa82eb8e65f7daa5df7bb04253568c66d3ca1e8500060b00ba0f71221")
  }
  func testMalformedMetadataAndOversizedLengthsAreRejected() {
    for value in ["<html>Access denied</html>", "d4:info9999999999:x", "d4:infod4:name1:xee", "d4:info\(info)eextra", "d4:info\(info)4:info\(info)e", "d4:infod6:lengthi-0eee", "d4:infod4:name08:demo.txtee"] {
      XCTAssertThrowsError(try TorrentMetadata.parse(Data(value.utf8)), value)
    }
    XCTAssertThrowsError(try TorrentMetadata.parse(Data(repeating: 0, count: TorrentMetadata.limit + 1)))
  }
  func testTorrentRecognitionDoesNotMisclassifyAnOrdinaryArchive() {
    XCTAssertTrue(TorrentMetadata.isTorrent(name: "SAMPLE.TORRENT"))
    XCTAssertTrue(TorrentMetadata.isTorrent(name: "metadata", mime: "application/x-bittorrent"))
    XCTAssertFalse(TorrentMetadata.isTorrent(name: "sample.zip"))
  }
}
