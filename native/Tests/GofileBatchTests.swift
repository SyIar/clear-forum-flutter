import Foundation
import XCTest
@testable import ForumCore

final class GofileBatchTests: XCTestCase {
  private func entry(_ id: String, _ name: String = "File.txt", folder: Bool = false) -> GofileEntry {
    GofileEntry(id: id, name: name, folder: folder, size: nil, mime: "", link: nil, thumbnail: nil, unavailable: false)
  }
  private func listing(_ id: String, _ entries: [GofileEntry], page: Int = 1, pages: Int = 1) -> GofileListing {
    GofileListing(id: id, title: "Test", entries: entries, page: page, pages: pages)
  }
  func testTraversesNestedFoldersAndTheirPagesBeforeNextSibling() throws {
    var plan = try GofileBatchPlan(listing: listing("root", [entry("folder", "Photos", folder: true), entry("last")]))
    XCTAssertEqual(plan.next?.entry.id, "folder")
    try plan.expand(listing("folder", [entry("first"), entry("nested", "More", folder: true)], pages: 2))
    XCTAssertEqual(plan.next?.path, ["Photos", "File.txt"])
    plan.advance()
    try plan.expand(listing("nested", [entry("second")]))
    XCTAssertEqual(plan.next?.path, ["Photos", "More", "File.txt"])
    plan.advance()
    XCTAssertEqual(plan.next?.entry.id, "folder")
    XCTAssertEqual(plan.next?.page, 2)
    try plan.expand(listing("folder", [entry("third")], page: 2, pages: 2))
    XCTAssertEqual(plan.next?.entry.id, "third")
    plan.advance()
    XCTAssertEqual(plan.next?.entry.id, "last")
    plan.advance()
    XCTAssertNil(plan.next)
  }
  func testCyclesDuplicatesAndAliasesDoNotDownloadTwice() throws {
    var plan = try GofileBatchPlan(listing: listing("root", [entry("a", folder: true), entry("alias", folder: true), entry("f")]))
    try plan.expand(listing("a", [entry("root", folder: true), entry("f"), entry("g")]))
    XCTAssertEqual(plan.next?.entry.id, "g")
    plan.advance()
    try plan.expand(listing("a", [entry("g")]))
    XCTAssertEqual(plan.next?.entry.id, "f")
    plan.advance(); XCTAssertNil(plan.next)
  }
  func testFilenameCollisionsAreRenamedAndPathsAreContained() throws {
    var plan = try GofileBatchPlan(listing: listing("root", [entry("a", "photo.png"), entry("b", "PHOTO.png"), entry("c", "../bad/name")]))
    XCTAssertEqual(plan.next?.path, ["photo.png"]); plan.advance()
    XCTAssertEqual(plan.next?.path, ["PHOTO (2).png"]); plan.advance()
    XCTAssertEqual(plan.next?.path, [".._bad_name"])
  }
  func testDownloadScopeStartsAtCurrentPageNotEveryRootPage() throws {
    let plan = try GofileBatchPlan(listing: listing("root", [entry("a")], page: 3, pages: 9))
    XCTAssertEqual(plan.pending.count, 1)
    XCTAssertEqual(plan.next?.entry.id, "a")
  }
  func testDepthLimitDoesNotDiscardPendingWork() throws {
    var plan = try GofileBatchPlan(listing: listing("root", [entry("d1", folder: true)]))
    for depth in 1...32 {
      try plan.expand(listing("d\(depth)", [entry("d\(depth + 1)", folder: true)]))
    }
    XCTAssertThrowsError(try plan.expand(listing("d33", [])))
    XCTAssertEqual(plan.next?.entry.id, "d33")
  }
  func testNativePasswordAndErrorStates() throws {
    let url = URL(string: "https://gofile.io/d/test")!
    let cases: [(String, Int, [String: Any], GofileFailure)] = [
      ("ok", 200, ["canAccess": false, "passwordRequired": true, "passwordWrong": true], .password(wrong: true)),
      ("ok", 200, ["canAccess": false, "expired": true], .expired),
      ("ok", 200, ["canAccess": false], .access),
      ("error-notFound", 200, [:], .notFound),
      ("error-notPremium", 403, [:], .premium)
    ]
    for (status, http, data, expected) in cases {
      let payload: [String: Any] = ["contentId": "test", "page": 1, "status": status, "httpStatus": http, "data": data]
      XCTAssertThrowsError(try GofileListing.parse(payload, requested: url, page: 1)) { error in
        XCTAssertEqual(error as? GofileFailure, expected)
      }
    }
    let payload: [String: Any] = ["contentId": "test", "page": 1, "status": "error", "httpStatus": 429, "retryAfter": 120]
    XCTAssertThrowsError(try GofileListing.parse(payload, requested: url, page: 1)) { error in
      XCTAssertGreaterThan((error as? GofileFailure)?.retryDate?.timeIntervalSinceNow ?? 0, 115)
    }
  }
}
