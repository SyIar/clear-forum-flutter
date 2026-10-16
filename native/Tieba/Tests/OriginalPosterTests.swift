import XCTest
@testable import TiebaCore

final class OriginalPosterTests: XCTestCase {
  func testOwnerReplyAndNestedReplyMatchThreadAuthorAcrossFloors() {
    let raw: JSON = ["id": "100", "floor": 42, "author": ["id": "7", "name": "Writer"],
      "sub_post_list": ["sub_post_list": [
        ["id": "101", "author": ["id": "7", "name": "Renamed writer"]],
        ["id": "102", "author": ["id": "8", "name": "Writer"]]
      ]]]
    let post = Post(raw, threadID: "20")
    XCTAssertTrue(post.isOriginalPoster("7"))
    XCTAssertEqual(post.replies.map { $0.isOriginalPoster("7") }, [true, false])
    XCTAssertFalse(post.isOriginalPoster("8"))
  }

  func testMissingProfilesRetainNumericIdentityWithoutGuessingFromFloorOrName() {
    let post = Post(["id": "1", "author_id": "7", "floor": 30], threadID: "20")
    XCTAssertTrue(post.isOriginalPoster("7"))
    XCTAssertFalse(post.isOriginalPoster(nil))
    XCTAssertFalse(post.isOriginalPoster(""))
    let anonymous = Post(["id": "2", "floor": 1], threadID: "20")
    XCTAssertFalse(anonymous.isOriginalPoster(""))
    XCTAssertFalse(anonymous.isOriginalPoster("7"))
    let zero = Post(["id": "3", "author_id": "0"], threadID: "20")
    XCTAssertFalse(zero.isOriginalPoster("0"))
  }
}
