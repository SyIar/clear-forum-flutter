import Foundation
import XCTest
@testable import ForumCore

final class BingWallpaperTests: XCTestCase {
  private func payload(base: String = "/th?id=OHR.Example_ZH-CN1234", allowed: Bool = true,
                       source: String = "https://www.bing.com/search?q=Example") throws -> Data {
    try JSONSerialization.data(withJSONObject: ["images": [["urlbase": base, "enddate": "20260930",
      "title": "Example landscape", "copyright": "Example photographer", "copyrightlink": source, "wp": allowed]]])
  }
  private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
  }
  func testArchivePrefersPortraitAndPreservesAttribution() throws {
    let wallpaper = try BingWallpaper.parse(payload())
    XCTAssertEqual(wallpaper.images.map { $0.absoluteString }, [
      "https://www.bing.com/th?id=OHR.Example_ZH-CN1234_1080x1920.jpg",
      "https://www.bing.com/th?id=OHR.Example_ZH-CN1234_1920x1080.jpg"])
    XCTAssertEqual(wallpaper.credit, "Example photographer")
    XCTAssertEqual(wallpaper.day, "20260930")
  }
  func testRestrictedMissingAndForeignImagesAreRejected() throws {
    XCTAssertThrowsError(try BingWallpaper.parse(payload(allowed: false)))
    XCTAssertThrowsError(try BingWallpaper.parse(Data(#"{"images":[]}"#.utf8)))
    for base in ["https://example.com/photo", "//example.com/photo", "/th?id=OHR.Example&other=1", "/th?id=OHR.Example\n"] {
      XCTAssertThrowsError(try BingWallpaper.parse(payload(base: base)))
    }
    XCTAssertEqual(try BingWallpaper.parse(payload(source: "https://bing.com.example.org")).source.absoluteString,
                   "https://www.bing.com")
  }
  func testNetworkTargetsRequireHTTPSBingAndNoCredentials() {
    for value in ["http://www.bing.com/th", "https://bing.com.example.org/th", "https://user@www.bing.com/th", "https://www.bing.com:444/th"] {
      XCTAssertFalse(BingWallpaper.accepts(URL(string: value)!))
    }
    XCTAssertTrue(BingWallpaper.accepts(URL(string: "https://cn.bing.com/th")!))
  }
  func testCacheExpiresAtLocalMidnightAndOldArchiveRetries() throws {
    let calendar = calendar("Asia/Shanghai")
    let before = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 23, minute: 59))!
    let after = before.addingTimeInterval(120)
    let snapshot = BingWallpaperSnapshot(wallpaper: try BingWallpaper.parse(payload()), image: Data(), checkedDay: "20260930")
    XCTAssertTrue(snapshot.isCurrent(at: before, calendar: calendar))
    XCTAssertFalse(snapshot.isCurrent(at: after, calendar: calendar))
    let lateArchive = BingWallpaperSnapshot(wallpaper: snapshot.wallpaper, image: Data(), checkedDay: "20261001")
    XCTAssertFalse(lateArchive.isCurrent(at: after, calendar: calendar))
  }
  func testMidnightUsesCalendarBoundariesAcrossDaylightSaving() {
    let calendar = calendar("America/Los_Angeles")
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
    let next = BingWallpaper.nextMidnight(after: start, calendar: calendar)
    XCTAssertEqual(next.timeIntervalSince(start), 25 * 3600)
    XCTAssertEqual(BingWallpaper.dayKey(next, calendar: calendar), "20261102")
  }
}
