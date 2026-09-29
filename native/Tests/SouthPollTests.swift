import Foundation
import XCTest
@testable import ForumCore

final class SouthPollTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private func form(results: [String] = Array(repeating: "*", count: 6), type: String? = "checkbox",
                    limit: Int? = 6, enabled: Bool = true, notice: String = "") -> String {
    let rows = results.enumerated().map { index, votes in
      let input = type.map { "<input type='\($0)' name='voteid[]' value='\(index)' onclick='checkVote(this)' \(enabled ? "" : "disabled")>" } ?? ""
      return "<tr><th width='40%'>\(input)Choice \(index + 1)</th><td><img src='images/colorImagination/tab-two.gif' width='0' height='15'>&nbsp;\(votes)&nbsp;\u{7968}</td></tr>"
    }.joined()
    return """
      <form action="job.php?action=vote" method="post" name="vote">
      <input type="hidden" name="verify" value="synthetic-token">
      <div class="tt2"><table><tr><th class="h" colspan="2"><span class="fr"><a href="read.php?tid-20-viewvoter-yes.html">View voters</a></span>
      \u{603b}\u{5171}\u{6709}<b>251</b>\u{4eba}\u{53c2}\u{4e0e}\u{672c}\u{6b21}\u{6295}\u{7968}
      \u{53d1}\u{8d77}\u{4e8e}\u{ff1a}2026-09-28 14:55 \u{81f3} 2026-10-28 14:55 \u{7ed3}\u{675f}</td></tr>
      \(rows)
      <tr><th class="tr4 s3">\(notice)</th><td class="tr4"><div>
      \(limit.map { "\u{9650}\u{9009}\u{4e2a}\u{6570}\u{ff1a}\($0)" } ?? "")
      <input type="hidden" name="tid" value="20">
      \(enabled ? "<input class='btn' type='submit' value='Submit'>" : "")
      </div></td></tr></table></div></form>
      """
  }
  private func page(_ poll: String, body: String = "Body text") throws -> ForumPage {
    try ForumParser().parse("""
      <html><title>A sample poll</title><body><h1 id="subject_tpc">Choose a drink</h1>
      \(poll)<form name="delatc"><input type="checkbox" name="selection[]">
      <article class="post"><div class="tpc_content" id="read_tpc">\(body)</div></article></form>
      </body></html>
      """, url: url)
  }
  func testSuppliedStructurePreservesSixHiddenResultsAndMetadata() throws {
    let result = try page(form())
    let poll = try XCTUnwrap(result.poll)
    XCTAssertEqual(poll.options.map(\.title), (1...6).map { "Choice \($0)" })
    XCTAssertEqual(poll.participants, 251)
    XCTAssertEqual(poll.maximumChoices, 6)
    XCTAssertEqual(poll.startsAt, "2026-09-28 14:55")
    XCTAssertEqual(poll.endsAt, "2026-10-28 14:55")
    XCTAssertTrue(poll.canVote)
    XCTAssertTrue(poll.resultsHidden)
    XCTAssertTrue(poll.options.allSatisfy { $0.votes == nil && poll.share(of: $0) == nil })
    XCTAssertNil(poll.totalVotes)
    XCTAssertEqual(result.posts.count, 1)
    XCTAssertEqual(result.posts[0].blocks.flatMap(\.runs).map(\.text).joined(), "Body text")
    XCTAssertFalse(String(describing: poll).contains("synthetic-token"))
  }
  func testVisibleResultsKeepZeroAndUseVotesRatherThanVotersForBars() throws {
    let poll = try XCTUnwrap(page(form(results: ["300", "100", "0"], limit: 3)).poll)
    XCTAssertEqual(poll.options.map(\.votes), [300, 100, 0])
    XCTAssertEqual(poll.totalVotes, 400)
    XCTAssertEqual(poll.share(of: poll.options[0]), 0.75)
    XCTAssertEqual(poll.share(of: poll.options[2]), 0)
    XCTAssertFalse(poll.resultsHidden)
    let zero = try XCTUnwrap(page(form(results: ["0", "0"], limit: 2)).poll)
    XCTAssertEqual(zero.totalVotes, 0)
    XCTAssertNil(zero.share(of: zero.options[0]))
  }
  func testSingleChoiceAndWebsiteSelectedState() throws {
    let html = form(type: "radio", limit: nil).replacingOccurrences(of: "value='2'", with: "value='2' checked")
    let poll = try XCTUnwrap(page(html).poll)
    XCTAssertEqual(poll.maximumChoices, 1)
    XCTAssertEqual(poll.options.filter(\.selected).map(\.id), [2])
  }
  func testResultsOnlyAndDisabledPollsStillDisplayOptions() throws {
    for html in [form(results: ["1,200", "800"], type: nil, limit: 2, enabled: false, notice: "Poll closed"),
                 form(results: ["1,200", "800"], limit: 2, enabled: false, notice: "Already voted")] {
      let poll = try XCTUnwrap(page(html).poll)
      XCTAssertFalse(poll.canVote)
      XCTAssertEqual(poll.options.count, 2)
      XCTAssertEqual(poll.totalVotes, 2000)
      XCTAssertFalse(poll.notice.isEmpty)
    }
  }
  func testUnknownCountsAndLimitsRemainUnknown() throws {
    let poll = try XCTUnwrap(page(form(results: ["*", "12", "unknown", "-1", "1.5", "999999999999999999999999"], limit: 99)).poll)
    XCTAssertEqual(poll.options.map(\.votes), [nil, 12, nil, nil, nil, nil])
    XCTAssertNil(poll.maximumChoices)
    XCTAssertNil(poll.totalVotes)
    XCTAssertNil(poll.share(of: poll.options[1]))
  }
  func testOtherFormsAndPostQuotesCannotBecomeTheThreadPoll() throws {
    for html in [form().replacingOccurrences(of: "name=\"vote\"", with: "name=\"other\""),
                 form().replacingOccurrences(of: "job.php?action=vote", with: "https://example.org/job.php?action=vote"),
                 form().replacingOccurrences(of: "job.php?action=vote", with: "job.php?action=buytopic"),
                 "<blockquote>\(form())</blockquote>"] {
      XCTAssertNil(try page(html).poll)
    }
    XCTAssertNil(try page("").poll)
    XCTAssertNil(try page("", body: form()).poll)
  }
  func testPollSurvivesPageCacheAndKeepsScrollAnchor() throws {
    let original = try page(form())
    let cache = PageCache()
    cache.store(original)
    cache.savePosition("poll", for: url)
    let cached = try XCTUnwrap(cache.value(for: url))
    XCTAssertEqual(cached.page.poll, original.poll)
    XCTAssertEqual(cached.visibleID, "poll")
  }
}
