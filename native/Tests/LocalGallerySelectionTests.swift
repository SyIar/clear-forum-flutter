import XCTest
@testable import ForumCore

final class LocalGallerySelectionTests: XCTestCase {
  private let entries = [
    LocalFileEntry(path: ["Album"], directory: true, bytes: nil, modified: nil),
    LocalFileEntry(path: ["Photo.png"], directory: false, bytes: 100, modified: nil),
    LocalFileEntry(path: ["Video.mp4"], directory: false, bytes: 200, modified: nil),
    LocalFileEntry(path: ["Notes.pdf"], directory: false, bytes: 300, modified: nil),
  ]

  func testSelectedFileAndFolderOrderArePreserved() throws {
    let selection = try XCTUnwrap(LocalGallerySelection(entries: entries, selected: ["Video.mp4"]))
    XCTAssertEqual(selection.files.map(\.name), ["Photo.png", "Video.mp4", "Notes.pdf"])
    XCTAssertEqual(selection.initialIndex, 1)
    XCTAssertEqual(selection.neighbor(of: 1, offset: -1), 0)
    XCTAssertEqual(selection.neighbor(of: 1, offset: 1), 2)
  }

  func testNoWrappingOrDirectorySelection() throws {
    let selection = try XCTUnwrap(LocalGallerySelection(entries: entries, selected: ["Photo.png"]))
    XCTAssertNil(selection.neighbor(of: 0, offset: -1))
    XCTAssertNil(selection.neighbor(of: 2, offset: 1))
    XCTAssertNil(selection.neighbor(of: -1, offset: 1))
    XCTAssertNil(selection.neighbor(of: 1, offset: 2))
    XCTAssertNil(LocalGallerySelection(entries: entries, selected: ["Album"]))
    XCTAssertNil(LocalGallerySelection(entries: [], selected: ["Photo.png"]))
  }

  func testOpenGalleryDoesNotChangeWhenTheFolderChanges() throws {
    var folder = entries
    let selection = try XCTUnwrap(LocalGallerySelection(entries: folder, selected: ["Video.mp4"]))
    folder.removeLast()
    folder.insert(LocalFileEntry(path: ["New.png"], directory: false, bytes: 42, modified: nil), at: 0)
    XCTAssertEqual(selection.files.count, 3)
    XCTAssertEqual(selection.files[selection.initialIndex].name, "Video.mp4")
  }

  func testDismissGestureLeavesHorizontalPagingAndZoomingAlone() {
    XCTAssertTrue(LocalGalleryDrag.canBegin(x: 20, y: 200, zoomed: false))
    XCTAssertFalse(LocalGalleryDrag.canBegin(x: 200, y: 20, zoomed: false))
    XCTAssertFalse(LocalGalleryDrag.canBegin(x: 50, y: 50, zoomed: false))
    XCTAssertFalse(LocalGalleryDrag.canBegin(x: 0, y: -200, zoomed: false))
    XCTAssertFalse(LocalGalleryDrag.canBegin(x: 0, y: 200, zoomed: true))
  }

  func testDismissThresholdSupportsCancelAndDeliberateFlick() {
    XCTAssertFalse(LocalGalleryDrag.shouldClose(distance: 40, velocity: 10, height: 800))
    XCTAssertTrue(LocalGalleryDrag.shouldClose(distance: 170, velocity: 0, height: 800))
    XCTAssertTrue(LocalGalleryDrag.shouldClose(distance: 40, velocity: 1000, height: 800))
    XCTAssertFalse(LocalGalleryDrag.shouldClose(distance: 5, velocity: 1000, height: 800))
    XCTAssertFalse(LocalGalleryDrag.shouldClose(distance: 200, velocity: -400, height: 800))
    XCTAssertFalse(LocalGalleryDrag.shouldClose(distance: 200, velocity: 0, height: 0))
  }
}
