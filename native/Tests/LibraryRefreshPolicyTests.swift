import Foundation
import XCTest
@testable import ForumCore

final class LibraryRefreshPolicyTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 2_000_000_000)
  func testSuccessfulChecksCannotBeRepeatedWithinOneHourEvenManually() {
    for manual in [false, true] {
      XCTAssertFalse(LibraryRefreshPolicy.isDue(checkedAt: now.addingTimeInterval(-3599), attemptedAt: nil, manual: manual, now: now))
      XCTAssertTrue(LibraryRefreshPolicy.isDue(checkedAt: now.addingTimeInterval(-3600), attemptedAt: nil, manual: manual, now: now))
    }
  }
  func testFailedOrCancelledChecksRequireManualRetryUntilAnHourPasses() {
    let success = now.addingTimeInterval(-7200), attempt = now.addingTimeInterval(-60)
    XCTAssertFalse(LibraryRefreshPolicy.isDue(checkedAt: success, attemptedAt: attempt, manual: false, now: now))
    XCTAssertTrue(LibraryRefreshPolicy.isDue(checkedAt: success, attemptedAt: attempt, manual: true, now: now))
    XCTAssertFalse(LibraryRefreshPolicy.isDue(checkedAt: nil, attemptedAt: attempt, manual: false, now: now))
    XCTAssertTrue(LibraryRefreshPolicy.isDue(checkedAt: nil, attemptedAt: attempt, manual: true, now: now))
    XCTAssertTrue(LibraryRefreshPolicy.isDue(checkedAt: success, attemptedAt: now.addingTimeInterval(-3600), manual: false, now: now))
  }
  func testNeverCheckedItemsAreEligibleAndRecentSuccessTakesPrecedence() {
    XCTAssertTrue(LibraryRefreshPolicy.isDue(checkedAt: nil, attemptedAt: nil, manual: false, now: now))
    XCTAssertFalse(LibraryRefreshPolicy.isDue(checkedAt: now, attemptedAt: now.addingTimeInterval(-7200), manual: true, now: now))
  }
  func testAllThreeModuleRecordsRetainAttemptDatesAcrossRelaunch() throws {
    let title = "\u{3010}Novel\u{3011}\u{7B2C}1\u{7AE0}"
    var book = BookhouseFollowedBook(entry: ForumEntry(title: title, url: BookhouseSitePolicy.thread("1")!, authorName: "Writer"))!
    book.attemptedAt = now
    let restoredBook = try JSONDecoder().decode(BookhouseFollowedBook.self, from: JSONEncoder().encode(book))
    XCTAssertEqual(restoredBook.attemptedAt, now)
    var author = SouthFollowedAuthor(id: "42", name: "Writer", followedAt: now)
    author.attemptedAt = now
    let restoredAuthor = try JSONDecoder().decode(SouthFollowedAuthor.self, from: JSONEncoder().encode(author))
    XCTAssertEqual(restoredAuthor.attemptedAt, now)
    var thread = ThreadReadState(); thread.attemptedAt = now
    let restoredThread = try JSONDecoder().decode(ThreadReadState.self, from: JSONEncoder().encode(thread))
    XCTAssertEqual(restoredThread.attemptedAt, now)
    let legacy = try JSONDecoder().decode(ThreadReadState.self, from: Data(#"{"latestMaximum":10}"#.utf8))
    XCTAssertNil(legacy.attemptedAt)
  }
}
