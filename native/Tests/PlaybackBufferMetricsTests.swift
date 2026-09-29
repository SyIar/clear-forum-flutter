import XCTest
@testable import ForumCore

final class PlaybackBufferMetricsTests: XCTestCase {
  func testCoverageDoesNotCountGapsOrOverlappingRangesTwice() {
    let result = PlaybackBufferMetrics(ranges: [(40, 50), (0, 10), (5, 20)], duration: 100, position: 8)
    XCTAssertEqual(result.fraction, 0.3)
    XCTAssertEqual(result.secondsAhead, 12)
    XCTAssertEqual(PlaybackBufferMetrics(ranges: [(0, 10), (40, 50)], duration: 100, position: 20).secondsAhead, 0)
  }
  func testUnknownDurationHasNoInventedPercentage() {
    for duration in [Double.nan, .infinity, 0, -1] {
      let result = PlaybackBufferMetrics(ranges: [(0, 8)], duration: duration, position: 0)
      XCTAssertNil(result.fraction)
      XCTAssertEqual(result.secondsAhead, 8)
    }
  }
  func testInvalidRangesAreIgnoredAndCoverageIsClipped() {
    let result = PlaybackBufferMetrics(ranges: [(-10, 5), (5, 200), (.nan, 20), (30, 10)], duration: 100, position: .nan)
    XCTAssertEqual(result.fraction, 1)
    XCTAssertEqual(result.secondsAhead, 0)
  }
  func testRateUsesTransferredBytesAndActiveTransferTimeThenExpires() {
    var rate = PlaybackTransferRate()
    XCTAssertEqual(rate.sample(bytes: 1000, transferDuration: 2, now: 10), 500)
    XCTAssertEqual(rate.sample(bytes: 5000, transferDuration: 4, now: 11), 2000)
    XCTAssertEqual(rate.sample(bytes: 5000, transferDuration: 4, now: 15), 2000)
    XCTAssertNil(rate.sample(bytes: 5000, transferDuration: 4, now: 17))
  }
  func testUnknownAndResetCountersNeverProduceFalseSpeed() {
    var rate = PlaybackTransferRate()
    XCTAssertNil(rate.sample(bytes: -1, transferDuration: -1, now: 0))
    XCTAssertNil(rate.sample(bytes: 0, transferDuration: 0, now: 1))
    XCTAssertNil(rate.sample(bytes: 100, transferDuration: 0, now: 2))
    XCTAssertEqual(rate.sample(bytes: 200, transferDuration: 1, now: 3), 200)
    XCTAssertNil(rate.sample(bytes: 10, transferDuration: 0.1, now: 4))
    XCTAssertNil(rate.sample(bytes: nil, transferDuration: nil, now: 5))
  }
}
