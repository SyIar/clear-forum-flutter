import Foundation
import XCTest
import ZIPFoundation
import ZipArchive
@testable import ForumCore

final class LocalArchiveExtractorTests: XCTestCase {
  private func fixture(_ run: (URL, LocalFileCatalog) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try run(root, LocalFileCatalog(root: root))
  }
  private func makeZIP(_ root: URL, entries: [(String, Data)], compressed: Bool = true) throws -> URL {
    let file = root.appendingPathComponent("Sample.zip")
    let archive = try Archive(url: file, accessMode: .create)
    for (name, data) in entries {
      try archive.addEntry(with: name, type: .file, uncompressedSize: Int64(data.count),
        compressionMethod: compressed ? .deflate : .none) { offset, count in
          data.subdata(in: Int(offset)..<(Int(offset) + count))
        }
    }
    return file
  }
  private func assertNoOutput(_ root: URL, catalog: LocalFileCatalog) throws {
    XCTAssertEqual(try catalog.entries().map(\.name), ["Sample.zip"])
  }
  private func makeEncryptedZIP(_ root: URL, aes: Bool, password: String = "test-password",
                                large: Bool = false) throws -> URL {
    let file = root.appendingPathComponent("Sample.zip")
    let zip = SSZipArchive(path: file.path)
    XCTAssertTrue(zip.open())
    defer { XCTAssertTrue(zip.close()) }
    XCTAssertTrue(zip.write(Data("Plain text".utf8), filename: "Readme.txt", withPassword: nil))
    XCTAssertTrue(zip.write(Data(), filename: "Empty.txt", compressionLevel: 0, password: password, aes: aes))
    let content = large ? Data(repeating: 42, count: 2 * 1024 * 1024) : Data("Protected text".utf8)
    XCTAssertTrue(zip.write(content, filename: "Nested/\u{6587}\u{4ef6}.txt", compressionLevel: 0, password: password, aes: aes))
    return file
  }

  func testTraditionalAndAESArchivesPromptThenExtractWithoutSavingPassword() throws {
    for aes in [false, true] {
      try fixture { root, catalog in
        let password = "Space \u{5bc6}\u{7801} #123 "
        _ = try makeEncryptedZIP(root, aes: aes, password: password)
        XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress())) {
          guard case LocalArchiveExtractor.Failure.passwordRequired = $0 else { return XCTFail("Expected a password request") }
        }
        try assertNoOutput(root, catalog: catalog)
        let progress = Progress()
        let folder = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: progress, password: password)
        XCTAssertEqual(try Data(contentsOf: catalog.url(for: folder + ["Nested", "\u{6587}\u{4ef6}.txt"])), Data("Protected text".utf8))
        XCTAssertEqual(try Data(contentsOf: catalog.url(for: folder + ["Empty.txt"])), Data())
        XCTAssertEqual(try catalog.storage(in: folder).files.count, 3)
        XCTAssertEqual(progress.fractionCompleted, 1)
      }
    }
  }

  func testWrongPasswordPublishesNothingAndCorrectRetrySucceeds() throws {
    for aes in [false, true] {
      try fixture { root, catalog in
        let file = try makeEncryptedZIP(root, aes: aes)
        let original = try Data(contentsOf: file)
        XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), password: "wrong")) {
          guard case LocalArchiveExtractor.Failure.incorrectPassword = $0 else { return XCTFail("Expected a password failure: \($0)") }
        }
        try assertNoOutput(root, catalog: catalog)
        XCTAssertEqual(try Data(contentsOf: file), original)
        _ = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), password: "test-password")
      }
    }
  }

  func testDamagedAESAuthenticationTrailerCannotPublishPlausiblePlaintext() throws {
    try fixture { root, catalog in
      let file = try makeEncryptedZIP(root, aes: true)
      var bytes = try Data(contentsOf: file)
      let central = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
      // The writer puts a signed data descriptor after the final encrypted entry.
      let descriptor = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x07, 0x08]), options: .backwards, in: 0..<central.lowerBound))
      bytes[descriptor.lowerBound - 1] ^= 1
      try bytes.write(to: file)
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), password: "test-password"))
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testEncryptedExtractionCanBeCancelledWithinOneLargeFile() throws {
    try fixture { root, catalog in
      _ = try makeEncryptedZIP(root, aes: true, large: true)
      let progress = Progress()
      let observer = progress.observe(\.completedUnitCount, options: [.new]) { value, _ in
        if value.completedUnitCount > 512 * 1024 { value.cancel() }
      }
      defer { observer.invalidate() }
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: progress, password: "test-password")) {
        XCTAssertTrue($0 is CancellationError)
      }
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testMixedPasswordsDoNotPublishOnlyTheSuccessfullyUnlockedEntries() throws {
    try fixture { root, catalog in
      let zip = SSZipArchive(path: root.appendingPathComponent("Sample.zip").path)
      XCTAssertTrue(zip.open())
      XCTAssertTrue(zip.write(Data([1]), filename: "One.txt", withPassword: "first"))
      XCTAssertTrue(zip.write(Data([2]), filename: "Two.txt", withPassword: "second"))
      XCTAssertTrue(zip.close())
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), password: "first"))
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testExtractsNestedUnicodeFilesAndKeepsOriginalZIP() throws {
    try fixture { root, catalog in
      let name = "Album/\u{56fe}\u{7247} 1.txt"
      let data = Data("Example contents".utf8)
      let file = try makeZIP(root, entries: [(name, data), ("Empty.txt", Data())])
      let original = try Data(contentsOf: file)
      let progress = Progress(totalUnitCount: 1)
      let result = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: progress)
      XCTAssertEqual(result, ["Sample"])
      XCTAssertEqual(try Data(contentsOf: catalog.url(for: result + ["Album", "\u{56fe}\u{7247} 1.txt"])), data)
      XCTAssertEqual(try Data(contentsOf: file), original)
      XCTAssertEqual(progress.fractionCompleted, 1)
      XCTAssertEqual(try catalog.storage(in: result).files.count, 2)
    }
  }

  func testDoesNotOverwriteExistingFolderOrFiles() throws {
    try fixture { root, catalog in
      _ = try makeZIP(root, entries: [("Photo.txt", Data([1, 2]))])
      let existing = root.appendingPathComponent("Sample")
      try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
      try Data([9]).write(to: existing.appendingPathComponent("Photo.txt"))
      let first = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress())
      let second = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress())
      XCTAssertEqual(first, ["Sample (2)"])
      XCTAssertEqual(second, ["Sample (3)"])
      XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("Photo.txt")), Data([9]))
    }
  }

  func testRejectsEscapingPathsBeforePublishingAnything() throws {
    for path in ["../escape", "/absolute", "folder/../../escape", "folder\\escape", "C:/escape", "folder//file"] {
      try fixture { root, catalog in
        _ = try makeZIP(root, entries: [("Good.txt", Data([1])), (path, Data([2]))])
        XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress()))
        try assertNoOutput(root, catalog: catalog)
      }
    }
  }

  func testRejectsSymbolicLinks() throws {
    try fixture { root, catalog in
      let archive = try Archive(url: root.appendingPathComponent("Sample.zip"), accessMode: .create)
      let target = Data("../outside".utf8)
      try archive.addEntry(with: "Link", type: .symlink, uncompressedSize: Int64(target.count)) { _, _ in target }
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress()))
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testEnforcesExpandedSizeAndFileCountLimits() throws {
    try fixture { root, catalog in
      _ = try makeZIP(root, entries: [("Large.txt", Data(repeating: 1, count: 1024)), ("Other.txt", Data([2]))])
      for limits in [LocalArchiveExtractor.Limits(entries: 1, bytes: 4096), LocalArchiveExtractor.Limits(entries: 10, bytes: 100)] {
        XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress(), limits: limits))
      }
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testRejectsOversizedDirectoryMetadataBeforeOpeningEngine() throws {
    try fixture { root, catalog in
      let file = try makeZIP(root, entries: [("File.txt", Data([1]))])
      var data = try Data(contentsOf: file)
      let offset = data.count - 22 + 12
      data.replaceSubrange(offset..<(offset + 4), with: [0, 0, 0, 4])
      try data.write(to: file)
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress())) {
        guard case LocalArchiveExtractor.Failure.tooLarge = $0 else { return XCTFail("Expected bounded directory metadata") }
      }
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testCancellationPreservesZIPAndDoesNotPublishPartialFolder() throws {
    try fixture { root, catalog in
      _ = try makeZIP(root, entries: [("Large.txt", Data(repeating: 1, count: 1024 * 1024))])
      let progress = Progress(totalUnitCount: 1)
      let observation = progress.observe(\.completedUnitCount, options: [.new]) { progress, _ in
        if progress.completedUnitCount > 0 { progress.cancel() }
      }
      defer { observation.invalidate() }
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: progress))
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testCorruptPayloadFailsChecksumAndDoesNotPublishPartialFolder() throws {
    try fixture { root, catalog in
      let payload = Data("UNIQUE-PAYLOAD-CHECKSUM".utf8)
      let file = try makeZIP(root, entries: [("Good.txt", Data([1])), ("Bad.txt", payload)], compressed: false)
      var data = try Data(contentsOf: file)
      let range = try XCTUnwrap(data.range(of: payload))
      data[range.lowerBound] ^= 1
      try data.write(to: file)
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress()))
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testEncryptedEntryCannotSilentlyTruncateExtraction() throws {
    try fixture { root, catalog in
      let file = try makeZIP(root, entries: [("First.txt", Data([1])), ("Encrypted.txt", Data([2]))], compressed: false)
      var data = try Data(contentsOf: file)
      let marker = Data([0x50, 0x4b, 0x01, 0x02])
      let first = try XCTUnwrap(data.range(of: marker))
      let second = try XCTUnwrap(data.range(of: marker, in: first.upperBound..<data.endIndex))
      data[second.lowerBound + 8] |= 1
      try data.write(to: file)
      XCTAssertThrowsError(try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress()))
      try assertNoOutput(root, catalog: catalog)
    }
  }

  func testReadsZIP64FooterWithoutLoadingWholeArchive() throws {
    try fixture { root, catalog in
      let file = try makeZIP(root, entries: [("File.txt", Data([7, 8]))], compressed: false)
      var data = try Data(contentsOf: file)
      let offset = data.count - 22
      var end = Data(data.suffix(22))
      func value(_ start: Int, _ count: Int) -> UInt64 {
        end[start..<(start + count)].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
      }
      func field(_ value: UInt64, _ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
      }
      let directorySize = value(12, 4), directoryOffset = value(16, 4)
      data.removeLast(22)
      for (value, length) in [(UInt64(0x06064b50), 4), (44, 8), (45, 2), (45, 2), (0, 4), (0, 4),
                             (1, 8), (1, 8), (directorySize, 8), (directoryOffset, 8),
                             (0x07064b50, 4), (0, 4), (UInt64(offset), 8), (1, 4)] {
        data.append(field(value, length))
      }
      for index in 8..<12 { end[index] = 0xff }
      data.append(end)
      try data.write(to: file)
      let result = try LocalArchiveExtractor.extract(["Sample.zip"], in: catalog, progress: Progress())
      XCTAssertEqual(try Data(contentsOf: catalog.url(for: result + ["File.txt"])), Data([7, 8]))
    }
  }
}
