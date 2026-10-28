import XCTest
@testable import ForumCore

final class VideoScrubStateTests: XCTestCase {
  func testFramesAreRequestedBeforeFingerReleaseAndOnlyLatestTargetIsKept() throws {
    var state = VideoScrubState(); state.begin()
    let first = try XCTUnwrap(state.update(10))
    XCTAssertNil(state.update(20)); XCTAssertNil(state.update(30)); XCTAssertNil(state.update(25))
    guard case .next(let next) = state.complete(first, succeeded: true) else { return XCTFail("Expected latest target") }
    XCTAssertEqual(next.seconds, 25)
    XCTAssertEqual(state.complete(next, succeeded: true), .waiting)
    XCTAssertNotNil(state.update(40))
  }
  func testReleaseWaitsForFinalFrameBeforeResuming() throws {
    var state = VideoScrubState(); state.begin()
    let first = try XCTUnwrap(state.update(10))
    XCTAssertNil(state.end(70))
    guard case .next(let last) = state.complete(first, succeeded: true) else { return XCTFail("Expected release target") }
    XCTAssertEqual(last.seconds, 70)
    XCTAssertEqual(state.complete(last, succeeded: true), .finished)
    XCTAssertNil(state.update(20))
  }
  func testDuplicateTargetsDoNotQueueDuplicateSeeks() throws {
    var state = VideoScrubState(); state.begin()
    let first = try XCTUnwrap(state.update(10))
    XCTAssertNil(state.update(10)); XCTAssertNil(state.end(10))
    XCTAssertEqual(state.complete(first, succeeded: true), .finished)
  }
  func testReleaseAfterCompletedPreviewAndAccessibilityOnlySeek() throws {
    var state = VideoScrubState(); state.begin()
    let preview = try XCTUnwrap(state.update(10))
    XCTAssertEqual(state.complete(preview, succeeded: true), .waiting)
    let end = try XCTUnwrap(state.end(12))
    XCTAssertEqual(state.complete(end, succeeded: true), .finished)
    state.begin()
    let accessibility = try XCTUnwrap(state.end(15))
    XCTAssertEqual(state.complete(accessibility, succeeded: true), .finished)
  }
  func testCancelledOrSupersededSeeksCannotRestartPlayback() throws {
    var state = VideoScrubState(); state.begin()
    let old = try XCTUnwrap(state.end(10)); state.cancel()
    XCTAssertEqual(state.complete(old, succeeded: true), .ignored)
    state.begin(); let current = try XCTUnwrap(state.end(10))
    XCTAssertEqual(state.complete(old, succeeded: true), .ignored)
    XCTAssertEqual(state.complete(current, succeeded: false), .failed)
  }
  func testInvalidTargetsAreIgnored() {
    var state = VideoScrubState(); state.begin()
    XCTAssertNil(state.update(.nan)); XCTAssertNil(state.update(.infinity)); XCTAssertNil(state.update(-1))
    XCTAssertNotNil(state.update(0))
  }
}
