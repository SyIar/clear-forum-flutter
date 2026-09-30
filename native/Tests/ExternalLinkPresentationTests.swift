import Foundation
import SwiftSoup
import XCTest
@testable import ForumCore

final class ExternalLinkPresentationTests: XCTestCase {
  func testMixedStyledAnchorsBecomeCompactLinksInOriginalOrder() throws {
    let html = """
    <div class='bbWrapper'><b>Complete archive - </b><span style='font-size:18px'>
    <a href='https://fileditchfiles.st/folder/demo.zip'><b>https://fileditchfiles.st/folder/demo.zip</b></a><br>
    <b>Mirror - </b><a href='https://filester.si/d/demo'><b><span>https://filester.si/d/demo</span></b></a></span></div>
    """
    let root = try XCTUnwrap(SwiftSoup.parseBodyFragment(html).body())
    let blocks = try SimpForumParser().parseBody(root, page: URL(string: "https://simpcity.cr/threads/demo.1/")!)
    let segments = blocks.flatMap { ExternalLinkPresentation.segments($0.runs, site: .simp) }
    XCTAssertEqual(segments.compactMap(\.url).map(\.absoluteString), ["https://fileditchfiles.st/folder/demo.zip", "https://filester.si/d/demo"])
    XCTAssertTrue(segments.filter { $0.url == nil }.map(\.label).joined().contains("Complete archive -"))
    XCTAssertTrue(segments.first?.runs.first?.bold == true)
    XCTAssertEqual(segments.filter { $0.url != nil }.map { ExternalLinkPresentation.title(url: $0.url!, label: $0.label, site: .simp) }, ["fileditch## demo.zip", "filester## demo"])
  }
  func testFormattedPiecesOfOneAnchorProduceOneChipWithoutChangingDestination() {
    let url = URL(string: "https://gofile.io/d/demo?key=example#part")!
    let runs = [TextRun(text: "Read "), TextRun(text: "Demo", bold: true, url: url), TextRun(text: " files", italic: true, url: url), TextRun(text: " next")]
    let parts = ExternalLinkPresentation.segments(runs, site: .south)
    XCTAssertEqual(parts.count, 3)
    XCTAssertEqual(parts[1].url, url)
    XCTAssertEqual(parts[1].label, "Demo files")
    XCTAssertEqual(ExternalLinkPresentation.title(url: url, label: parts[1].label, site: .south), "gofile## Demo files")
    XCTAssertEqual(parts.flatMap(\.runs), runs)
  }
  func testInternalLinksAndInlineEmoticonsRemainInText() {
    let local = URL(string: "https://south-plus.net/read.php?tid-10.html")!
    let face = URL(string: "https://south-plus.net/images/post/smile/smallface/face077.gif")!
    let runs = [TextRun(text: "See "), TextRun(text: "thread", url: local), TextRun(text: "Smile", emoticon: face)]
    let parts = ExternalLinkPresentation.segments(runs, site: .south)
    XCTAssertEqual(parts.count, 1)
    XCTAssertNil(parts[0].url)
    XCTAssertEqual(parts[0].runs, runs)
    XCTAssertEqual(ExternalLinkPresentation.title(url: local, label: "thread", site: .south), "thread")
  }
  func testPrefixesUseProviderAndRawAddressesUseReadableFilename() {
    for (address, expected) in [
      ("https://bunkrr.su/f/demo", "bunkr## demo"),
      ("https://pixeldra.in/u/demo", "pixeldrain## demo"),
      ("https://filester.gg/d/demo", "filester## demo"),
      ("http://gofile.io/d/demo", "gofile## demo"),
      ("https://example.org/files/demo%20archive.zip?token=example", "example.org## demo archive.zip")
    ] {
      let url = URL(string: address)!
      XCTAssertEqual(ExternalLinkPresentation.title(url: url, label: address, site: .simp), expected)
    }
    let url = URL(string: "https://bunkr.si/f/demo")!
    XCTAssertEqual(ExternalLinkPresentation.title(url: url, label: "\n Nature.mp4 \n", site: .simp), "bunkr## Nature.mp4")
    XCTAssertEqual(ExternalLinkPresentation.title(url: URL(string: "https://filester.si.evil.com/d/demo")!, label: "Demo", site: .simp), "filester.si.evil.com## Demo")
  }
  func testSouthAutoDetectedLinksUseTheSamePresentation() throws {
    let root = try XCTUnwrap(SwiftSoup.parseBodyFragment("Files: https://gofile.io/d/demo and https://filester.si/d/mirror").body())
    let blocks = try SouthBodyParser().parseBody(root, page: SouthSitePolicy.start)
    let segments = blocks.flatMap { ExternalLinkPresentation.segments($0.runs, site: .south) }
    XCTAssertEqual(segments.compactMap(\.url).count, 2)
    XCTAssertEqual(segments.filter { $0.url == nil }.map(\.label).joined(), "Files:  and ")
  }
}
