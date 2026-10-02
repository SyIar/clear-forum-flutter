import Foundation
import XCTest
@testable import ForumCore

final class LocalFileCatalogTests: XCTestCase {
  private func fixture(_ run: (URL, LocalFileCatalog) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try run(root, LocalFileCatalog(root: root))
  }

  func testListsFoldersFirstWithNaturalNamesAndSizes() throws {
    try fixture { root, catalog in
      try FileManager.default.createDirectory(at: root.appendingPathComponent("Images"), withIntermediateDirectories: true)
      try Data([1, 2, 3]).write(to: root.appendingPathComponent("Video10.mp4"))
      try Data([1]).write(to: root.appendingPathComponent("Video2.mp4"))
      try Data().write(to: root.appendingPathComponent(".private"))
      let entries = try catalog.entries()
      XCTAssertEqual(entries.map(\.name), ["Images", "Video2.mp4", "Video10.mp4"])
      XCTAssertNil(entries[0].bytes)
      XCTAssertEqual(entries[2].bytes, 3)
      XCTAssertNotNil(entries[2].modified)
    }
  }

  func testBrowsesNestedFilesAndRefreshesAfterAFileIsMoved() throws {
    try fixture { root, catalog in
      let path = ["Gofile Downloads", "Album", "Photo #1%.png"]
      let folder = root.appendingPathComponent("Gofile Downloads/Album")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let file = folder.appendingPathComponent(path.last!)
      try Data([1]).write(to: file)
      XCTAssertEqual(try catalog.entries(in: Array(path.dropLast())).first?.path, path)
      XCTAssertEqual(try Data(contentsOf: catalog.url(for: path)), Data([1]))
      XCTAssertThrowsError(try catalog.entries(in: path))
      try FileManager.default.moveItem(at: file, to: folder.appendingPathComponent("renamed.png"))
      XCTAssertThrowsError(try catalog.url(for: path))
      XCTAssertEqual(try catalog.entries(in: Array(path.dropLast())).map(\.name), ["renamed.png"])
    }
  }

  func testRejectsTraversalAndRemoteRoots() throws {
    try fixture { _, catalog in
      for path in [[".."], ["."], [""], ["sub/file"], ["sub\\file"], ["bad\0file"]] {
        XCTAssertThrowsError(try catalog.url(for: path))
      }
      XCTAssertThrowsError(try LocalFileCatalog(root: URL(string: "https://example.com")!).entries())
    }
  }

  func testDoesNotExposeSymlinkedFilesOrDirectories() throws {
    try fixture { root, catalog in
      let folder = root.appendingPathComponent("real")
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try Data([1]).write(to: folder.appendingPathComponent("photo.png"))
      try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: folder)
      try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: root.deletingLastPathComponent())
      try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("file.png"), withDestinationURL: folder.appendingPathComponent("photo.png"))
      XCTAssertEqual(try catalog.entries().map(\.name), ["real"])
      XCTAssertThrowsError(try catalog.url(for: ["alias", "photo.png"]))
      XCTAssertThrowsError(try catalog.url(for: ["outside"]))
      XCTAssertThrowsError(try catalog.url(for: ["file.png"]))
    }
  }
}
