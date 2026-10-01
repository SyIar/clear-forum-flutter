import Foundation
import XCTest
@testable import ForumCore

final class DownloadLinkTests: XCTestCase {
  func testGofilePagesAndDirectFilesUseTheExistingBrowser() {
    let expected = DownloadLink.gofile(URL(string: "https://gofile.io/d/ExampleID")!)
    XCTAssertEqual(DownloadLink.parse(" \nhttps://gofile.io/d/ExampleID\n"), expected)
    XCTAssertEqual(DownloadLink.parse("http://www.gofile.io:80/d/ExampleID"), expected)
    XCTAssertEqual(DownloadLink.parse("https://store1.gofile.io/download/web/ExampleID/demo.mp4"), expected)
  }

  func testSupportedHostsAndAliasesRetainFileAndAlbumRoutes() {
    for address in ["https://bunkr.media/f/Demo", "https://bunkr.cr/a/Album",
                    "https://pixeldrain.com/l/Demo", "https://pixeldra.in/u/Torrent",
                    "https://filester.si/d/Demo", "https://filester.me/f/Folder",
                    "https://fileditchfiles.st/folder/demo.zip"] {
      XCTAssertEqual(DownloadLink.parse(address), .hosted(URL(string: address)!), address)
    }
  }

  func testHTTPUpgradePreservesEncodedPathsAndSignedQueries() {
    let suffix = "fileditchfiles.st/folder/demo%20file.zip?token=a%2Bb%2Fc&part=1"
    XCTAssertEqual(DownloadLink.parse("http://" + suffix), .hosted(URL(string: "https://" + suffix)!))
    XCTAssertEqual(DownloadLink.parse("http://filester.si:80/d/CaseSensitiveID"),
                   .hosted(URL(string: "https://filester.si/d/CaseSensitiveID")!))
  }

  func testRejectsNonWebLinksCredentialsAndMultipleInputs() {
    for input in ["", "  ", "filester.si/d/Demo", "file:///tmp/demo.zip", "javascript:alert(1)",
                  "https:///d/Demo", "https://user:pass@filester.si/d/Demo",
                  "https://filester.si/d/Demo https://gofile.io/d/Other",
                  "https://filester.si/d/De\nmo", "https://filester.si/d/De\u{0000}mo",
                  "https://filester.si/d/" + String(repeating: "a", count: 8192)] {
      XCTAssertNil(DownloadLink.parse(input), input)
    }
  }

  func testUnsupportedPagesDoNotStartAFileTransferOrChangeTheirURL() {
    for address in ["http://example.com/article?file=demo.zip", "https://filester.si/",
                    "https://filester.si.evil.com/d/Demo", "https://bunkr.cr:8443/a/Demo",
                    "http://gofile.io:8080/d/Demo"] {
      XCTAssertEqual(DownloadLink.parse(address), .unsupported(URL(string: address)!), address)
    }
  }
}
