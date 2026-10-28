import Foundation
import XCTest
@testable import ForumCore

final class LibraryCheckProgressTests: XCTestCase {
  func testLiveSuccessRemovesFailureCountAndReason() {
    var state = LibraryCheckProgress(running: true, total: 1)
    let attempt = state.beginThread("thread-a")
    XCTAssertTrue(state.failThread("thread-a", attempt: attempt, reason: .verification))
    XCTAssertEqual(state.failed, 1)
    XCTAssertEqual(state.threadFailures["thread-a"], .verification)
    XCTAssertTrue(state.resolveThread("thread-a"))
    XCTAssertEqual(state.failed, 0)
    XCTAssertTrue(state.threadFailures.isEmpty)
    XCTAssertFalse(state.resolveThread("thread-a"))
    XCTAssertEqual(state.failed, 0)
  }

  func testLateBackgroundFailureCannotOverwriteLiveSuccess() {
    var state = LibraryCheckProgress()
    let attempt = state.beginThread("thread-a")
    state.resolveThread("thread-a")
    XCTAssertFalse(state.failThread("thread-a", attempt: attempt, reason: .verification))
    XCTAssertEqual(state.failed, 0)
    XCTAssertTrue(state.threadFailures.isEmpty)
  }

  func testNewLiveReadInvalidatesOldRequestWithoutInventingSuccess() {
    var state = LibraryCheckProgress()
    let attempt = state.beginThread("thread-a")
    state.supersedeThread("thread-a")
    XCTAssertFalse(state.failThread("thread-a", attempt: attempt, reason: .verification))
    let retry = state.beginThread("thread-a")
    XCTAssertTrue(state.failThread("thread-a", attempt: retry, reason: .verification))
    state.supersedeThread("thread-a")
    XCTAssertEqual(state.threadFailures["thread-a"], .verification)
    XCTAssertEqual(state.failed, 1)
  }

  func testRecoveringOneThreadPreservesOtherThreadsAndAuthorFailures() {
    var state = LibraryCheckProgress()
    state.failed = 1 // A followed-author check failed independently.
    let first = state.beginThread("thread-a")
    let second = state.beginThread("thread-b")
    state.failThread("thread-a", attempt: first, reason: .verification)
    state.failThread("thread-b", attempt: second, reason: .network)
    state.resolveThread("thread-a")
    XCTAssertEqual(state.failed, 2)
    XCTAssertEqual(state.threadFailures, ["thread-b": .network])
  }

  func testRetryIgnoresPreviousAttemptAndDoesNotDoubleCount() {
    var state = LibraryCheckProgress()
    let old = state.beginThread("thread-a")
    state.failThread("thread-a", attempt: old, reason: .verification)
    let retry = state.beginThread("thread-a")
    XCTAssertEqual(state.failed, 0)
    XCTAssertFalse(state.failThread("thread-a", attempt: old, reason: .verification))
    XCTAssertTrue(state.failThread("thread-a", attempt: retry, reason: .network))
    XCTAssertFalse(state.failThread("thread-a", attempt: retry, reason: .network))
    XCTAssertEqual(state.failed, 1)
  }

  func testFailedAttemptThrottleDoesNotPreventRecordingAnOpenedPage() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    var reading = ThreadReadState()
    reading.attemptedAt = now
    XCTAssertFalse(LibraryRefreshPolicy.isDue(checkedAt: nil, attemptedAt: reading.attemptedAt, manual: false, now: now))
    XCTAssertTrue(LibraryRefreshPolicy.isDue(checkedAt: nil, attemptedAt: nil, manual: false, now: now))
    reading.opened(maximum: 120, at: now)
    XCTAssertFalse(LibraryRefreshPolicy.isDue(checkedAt: reading.checkedAt, attemptedAt: reading.attemptedAt, manual: true, now: now))
    XCTAssertEqual(reading.latestMaximum, 120)
    XCTAssertEqual(reading.seenMaximum, 120)
  }

  func testOldBatchFailureCannotAffectNewBatch() {
    var state = LibraryCheckProgress()
    let old = state.beginThread("thread-a")
    state = LibraryCheckProgress(running: true, total: 1)
    let current = state.beginThread("thread-a")
    XCTAssertFalse(state.failThread("thread-a", attempt: old, reason: .verification))
    XCTAssertTrue(state.failThread("thread-a", attempt: current, reason: .network))
    XCTAssertEqual(state.failed, 1)
  }
}
