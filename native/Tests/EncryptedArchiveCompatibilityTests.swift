import Foundation
import XCTest
@testable import ForumCore

final class EncryptedArchiveCompatibilityTests: XCTestCase {
  // Independent, pre-existing AE-1/Deflate fixture from ZipArchive 2.6.0.
  // https://github.com/ZipArchive/ZipArchive/tree/2.6.0/Example/ObjectiveCExampleTests/Fixtures
  // Covered by the bundled ZipArchive MIT license; test password is public.
  private let fixture = Data(base64Encoded: """
    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
    AOoHAAAAAA==
    """, options: .ignoreUnknownCharacters)!

  func testExistingAESDeflateArchiveAndAuthenticationFailure() throws {
    for damaged in [false, true] {
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: root) }
      var data = fixture
      if damaged {
        let directory = try XCTUnwrap(data.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        data[directory.lowerBound - 1] ^= 1
      }
      try data.write(to: root.appendingPathComponent("Sample.zip"))
      let catalog = LocalFileCatalog(root: root)
      if damaged {
        XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), password: "passw0rd"))
        XCTAssertEqual(try catalog.entries().map(\.name), ["Sample.zip"])
      } else {
        let folder = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), password: "passw0rd")
        let readme = try Data(contentsOf: catalog.url(for: folder + ["README.md"]))
        XCTAssertEqual(readme.count, 2697)
        XCTAssertTrue(String(decoding: readme, as: UTF8.self).contains("ZipArchive"))
        XCTAssertEqual(try catalog.storage(in: folder).bytes, 3774)
      }
    }
  }
}
