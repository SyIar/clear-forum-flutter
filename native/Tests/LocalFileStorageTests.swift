import Foundation
import XCTest
@testable import ForumCore

final class LocalFileStorageTests: XCTestCase {
  private func fixture(_ run: (URL, LocalFileCatalog) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try run(root, LocalFileCatalog(root: root))
  }

  func testRecursivelyTotalsFilesAndSortsLargestFirstWithStableTies() throws {
    try fixture { root, catalog in
      let sub = root.appendingPathComponent("Album")
      try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
      try Data(repeating: 1, count: 300).write(to: sub.appendingPathComponent("Large.mp4"))
      try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("Photo10.jpg"))
      try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("Photo2.jpg"))
      try Data([1]).write(to: root.appendingPathComponent(".Hidden"))
      let snapshot = try catalog.storage()
      XCTAssertEqual(snapshot.bytes, 501)
      XCTAssertEqual(snapshot.files.map(\.name), ["Large.mp4", "Photo2.jpg", "Photo10.jpg", ".Hidden"])
      XCTAssertEqual(snapshot.files[0].path, ["Album", "Large.mp4"])
      XCTAssertEqual(snapshot.skipped, 0)
      XCTAssertEqual(try catalog.storage(in: ["Album"]).bytes, 300)
    }
  }

  func testDeletesSelectedFileAndRecountsWithoutAffectingSameNameElsewhere() throws {
    try fixture { root, catalog in
      let sub = root.appendingPathComponent("Album")
      try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
      try Data([1, 2, 3]).write(to: sub.appendingPathComponent("Same.txt"))
      try Data([4]).write(to: root.appendingPathComponent("Same.txt"))
      let selected = try XCTUnwrap(catalog.storage().files.first)
      try catalog.remove(selected)
      XCTAssertEqual(try catalog.storage().bytes, 1)
      XCTAssertEqual(try Data(contentsOf: catalog.url(for: ["Same.txt"])), Data([4]))
    }
  }

  func testDeletesSelectedFolderRecursivelyButRejectsRootAndChangedFiles() throws {
    try fixture { root, catalog in
      let sub = root.appendingPathComponent("Album/Sub")
      try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
      try Data([1]).write(to: sub.appendingPathComponent("File.txt"))
      let file = try XCTUnwrap(catalog.storage().files.first)
      try Data([2, 3]).write(to: sub.appendingPathComponent("File.txt"))
      XCTAssertThrowsError(try catalog.remove(file))
      let folder = try XCTUnwrap(catalog.entries().first)
      try catalog.remove(folder)
      XCTAssertTrue(try catalog.entries().isEmpty)
      XCTAssertThrowsError(try catalog.remove(LocalFileEntry(path: [], directory: true, bytes: nil, modified: nil)))
      XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    }
  }

  func testAnalysisAndDeletionDoNotFollowSymlinksOutsideDocuments() throws {
    try fixture { root, catalog in
      let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try Data([9, 8, 7]).write(to: outside)
      defer { try? FileManager.default.removeItem(at: outside) }
      let folder = root.appendingPathComponent("Album")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Link"), withDestinationURL: outside)
      let snapshot = try catalog.storage()
      XCTAssertEqual(snapshot.bytes, 0)
      XCTAssertEqual(snapshot.skipped, 1)
      XCTAssertThrowsError(try catalog.remove(LocalFileEntry(path: ["Album", "Link"], directory: false, bytes: nil, modified: nil)))
      try catalog.remove(XCTUnwrap(catalog.entries().first))
      XCTAssertEqual(try Data(contentsOf: outside), Data([9, 8, 7]))
    }
  }
}
