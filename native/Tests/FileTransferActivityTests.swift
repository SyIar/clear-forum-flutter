import XCTest
@testable import ForumCore

final class FileTransferActivityTests: XCTestCase {
  func testActiveFileIsNotReportedAsStillQueued() {
    XCTAssertEqual(FileTransferActivity.waiting.queuedCount(pending: 1, running: true), 1)
    for stage in [FileTransferActivity.resolving, .downloading, .saving] {
      XCTAssertEqual(stage.queuedCount(pending: 1, running: true), 0)
      XCTAssertEqual(stage.queuedCount(pending: 3, running: true), 2)
    }
  }
  func testPausedAndAdvancedPlansKeepTheCorrectRemainingCount() {
    XCTAssertEqual(FileTransferActivity.downloading.queuedCount(pending: 3, running: false), 3)
    XCTAssertEqual(FileTransferActivity.waiting.queuedCount(pending: 2, running: true), 2)
    XCTAssertEqual(FileTransferActivity.readingFolder.queuedCount(pending: 3, running: true), 2)
    XCTAssertEqual(FileTransferActivity.saving.queuedCount(pending: 0, running: true), 0)
  }
}
