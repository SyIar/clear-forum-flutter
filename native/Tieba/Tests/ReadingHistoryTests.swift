import Foundation
import XCTest
@testable import TiebaCore

final class ReadingHistoryTests: XCTestCase {
  func testMaximumReadFloorSurvivesReturningToAnEarlierPage() {
    var library = LocalLibrary(document: ["history": []])
    library.remember(thread: "thread", title: "Title", forum: "Forum", post: "post40", page: 2, onlyAuthor: false, floor: 40)
    library.remember(thread: "thread", title: "Title", forum: "Forum", post: "post5", page: 1, onlyAuthor: false, floor: 5)
    let row = library.rows("history").first!
    XCTAssertEqual(integer(row["maximumFloor"]), 40)
    XCTAssertEqual(string(row["lastPostId"]), "post5")
    XCTAssertEqual(integer(row["page"]), 1)
    XCTAssertEqual(library.rows("history").count, 1)
  }
}
