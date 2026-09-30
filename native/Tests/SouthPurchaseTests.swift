import Foundation
import XCTest
@testable import ForumCore

final class SouthPurchaseTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private let priceLabel = "\u{6B64}\u{5E16}\u{552E}\u{4EF7}"
  private let currency = "SP\u{5E01}"
  private func markup(price: String = "0", pid: String = "tpc", action: String? = nil, quoted: Bool = false) -> String {
    let action = action ?? "job.php?action=buytopic&amp;tid=20&amp;pid=\(pid)&amp;verify=synthetic_token"
    let gate = "<h6 class='quote jumbotron'><span class='s3'>\(priceLabel) \(price) \(currency), 713 buyers</span><input type='button' onclick=\"location.href='\(action)'\"></h6>"
    return "<table class='js-post'><tr><td><div class='tpc_content'><div id='read_\(pid)'>Before \(quoted ? "<blockquote>\(gate)</blockquote>" : gate) After</div></div></td></tr></table>"
  }
  private func parse(_ body: String) throws -> ForumPage {
    try ForumParser().parse("<html><h1 id='subject_tpc'>Sample</h1>\(body)</html>", url: url)
  }
  private func offer(_ price: Decimal = 0, pid: String = "tpc", token: String = "synthetic_token") -> SouthPurchaseOffer {
    SouthPurchaseOffer(threadID: "20", postID: pid, price: price,
      action: URL(string: "https://south-plus.net/job.php?action=buytopic&tid=20&pid=\(pid)&verify=\(token)")!)
  }
  private func page(_ offers: [SouthPurchaseOffer]) -> ForumPage {
    let posts = offers.isEmpty ? [ForumPost(id: "post_tpc", author: "Reader", date: "", number: "", blocks: [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Unlocked content")])])] :
      offers.map { ForumPost(id: "post_" + $0.postID, author: "Reader", date: "", number: "", blocks: [BodyBlock(kind: .purchase, purchase: $0)]) }
    return ForumPage(url: url, title: "Sample", kind: .posts, entries: [], posts: posts, pageNumber: 1, loggedIn: true)
  }
  func testParsesRealButtonShapeBeforeInputSanitization() throws {
    let result = try parse(markup() + markup(price: "5.50", pid: "123"))
    XCTAssertEqual(result.purchaseOffers.count, 2)
    XCTAssertTrue(result.purchaseOffers[0].isFree)
    XCTAssertEqual(result.purchaseOffers[1].priceText, "5.5")
    XCTAssertFalse(result.purchaseOffers[1].isFree)
    XCTAssertEqual(result.posts[0].blocks.map(\.kind), [.paragraph, .purchase, .paragraph])
    XCTAssertTrue(try parse(markup(quoted: true)).purchaseOffers.isEmpty)
  }
  func testUnknownPricesNeverDefaultToFree() throws {
    for price in ["-1", "free", "?", "0e2", "0.001", "1,000", "999999999", "+0", "0 USD"] {
      XCTAssertTrue(try parse(markup(price: price)).purchaseOffers.isEmpty, price)
    }
    XCTAssertTrue(try parse(markup(price: "0.00")).purchaseOffers[0].isFree)
    XCTAssertTrue(try parse(markup().replacingOccurrences(of: currency, with: "HP")).purchaseOffers.isEmpty)
  }
  func testRejectsUnrelatedActionsOriginsPostsAndDuplicateParameters() throws {
    for action in [
      "https://evil.example/job.php?action=buytopic&tid=20&pid=tpc&verify=x",
      "job.php?action=buytopic&tid=21&pid=tpc&verify=x",
      "job.php?action=buytopic&tid=20&pid=123&verify=x",
      "job.php?action=delete&tid=20&pid=tpc&verify=x",
      "job.php?action=buytopic&tid=20&pid=tpc&verify=x&tid=21",
      "job.php?action=buytopic&tid=20&pid=tpc&verify=x&extra=1",
      "job.php?action=buytopic&tid=20&pid=tpc&verify=",
      "job.php?action=buytopic&tid=20&pid=tpc&verify=x#fragment"
    ] { XCTAssertTrue(try parse(markup(action: action)).purchaseOffers.isEmpty) }
    let injected = markup().replacingOccurrences(of: "location.href=", with: "track();location.href=")
    XCTAssertTrue(try parse(injected).purchaseOffers.isEmpty)
    let mismatched = markup().replacingOccurrences(of: "synthetic_token'", with: "synthetic_token&quot;")
    XCTAssertTrue(try parse(mismatched).purchaseOffers.isEmpty)
  }
  func testRequestSendsOnlyMatchingSouthCookiesAndReferer() throws {
    let own = try XCTUnwrap(HTTPCookie(properties: [.name: "session", .value: "synthetic", .domain: "south-plus.net", .path: "/", .secure: "TRUE"]))
    let foreign = try XCTUnwrap(HTTPCookie(properties: [.name: "other", .value: "synthetic", .domain: "simpcity.cr", .path: "/", .secure: "TRUE"]))
    let narrow = try XCTUnwrap(HTTPCookie(properties: [.name: "readOnly", .value: "synthetic", .domain: "south-plus.net", .path: "/read.php", .secure: "TRUE"]))
    let request = try SouthPurchase.request(offer(), page: url, userAgent: "Test agent", cookies: [own, foreign, narrow])
    XCTAssertEqual(request.httpMethod, "GET")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=synthetic")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Referer"), url.absoluteString)
    XCTAssertFalse(request.httpShouldHandleCookies)
  }
  @MainActor func testAutomaticBatchBuysAllFreeOffersButNoPaidOffers() async throws {
    var current = page([offer(), offer(0, pid: "123"), offer(9, pid: "456")])
    var submitted: [String] = []
    var reads = 0
    let result = try await SouthPurchaseService().unlockFree(in: current, load: { _ in reads += 1; return current }, submit: { selected, _ in
      submitted.append(selected.postID)
      let index = current.posts.firstIndex { $0.id == "post_" + selected.postID }!
      current.posts[index].blocks = [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Unlocked content")])]
    })
    XCTAssertEqual(submitted, ["tpc", "123"])
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(result.page.purchaseOffers.map(\.priceText), ["9"])
    XCTAssertNil(result.message)
  }
  @MainActor func testFreeToPaidPriceChangeDoesNotSubmit() async throws {
    var submissions = 0
    let result = try await SouthPurchaseService().unlockFree(in: page([offer()]), load: { _ in self.page([self.offer(3)]) }, submit: { _, _ in submissions += 1 })
    XCTAssertEqual(submissions, 0)
    XCTAssertEqual(result.page.purchaseOffers.first?.price, 3)
    XCTAssertNotNil(result.message)
  }
  @MainActor func testBlockedAuthorsAreNeverAutomaticallyPurchasedAndStayInRawPage() async throws {
    var current = page([offer(), offer(0, pid: "123")])
    current.posts[0].authorID = "101"
    current.posts[1].authorID = "102"
    var submitted: [String] = []
    let result = try await SouthPurchaseService().unlockFree(in: current, excludingAuthors: ["101"], load: { _ in current }, submit: { selected, _ in
      submitted.append(selected.postID)
      let index = current.posts.firstIndex { $0.id == "post_" + selected.postID }!
      current.posts[index].blocks = [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Unlocked content")])]
    })
    XCTAssertEqual(submitted, ["123"])
    XCTAssertEqual(result.page.posts.first?.authorID, "101")
    XCTAssertEqual(result.page.purchaseOffers.count, 1)
    XCTAssertTrue(result.page.purchaseOffers(excludingAuthors: ["101"]).isEmpty)
  }
  @MainActor func testFreshAuthorIdentityIsCheckedBeforePurchase() async throws {
    let original = page([offer()])
    var fresh = original
    fresh.posts[0].authorID = "101"
    var submitted = false
    let result = try await SouthPurchaseService().unlockFree(in: original, excludingAuthors: ["101"], load: { _ in fresh }, submit: { _, _ in submitted = true })
    XCTAssertFalse(submitted)
    XCTAssertEqual(result.page.posts.first?.authorID, "101")
  }
  @MainActor func testManualPurchaseUsesFreshTokenAndRefreshesAfterSubmitting() async throws {
    let accepted = offer(3, token: "old_token")
    let fresh = offer(3, token: "new_token")
    var current = page([fresh])
    var submitted: [SouthPurchaseOffer] = []
    let result = try await SouthPurchaseService().buy(accepted, page: page([accepted]), load: { _ in current }, submit: { selected, _ in
      submitted.append(selected); current = self.page([])
    })
    XCTAssertEqual(submitted, [fresh])
    XCTAssertTrue(result.page.purchaseOffers.isEmpty)
  }
  @MainActor func testPaidPriceChangeRequiresAnotherClick() async throws {
    var submitted = false
    let result = try await SouthPurchaseService().buy(offer(3), page: page([offer(3)]), load: { _ in self.page([self.offer(5)]) }, submit: { _, _ in submitted = true })
    XCTAssertFalse(submitted)
    XCTAssertEqual(result.page.purchaseOffers.first?.price, 5)
    XCTAssertNotNil(result.message)
  }
  @MainActor func testAlreadyUnlockedAndStillLockedResponsesDoNotLoop() async throws {
    var submissions = 0
    let service = SouthPurchaseService(pause: { _ in })
    let unlocked = try await service.buy(offer(), page: page([offer()]), load: { _ in self.page([]) }, submit: { _, _ in submissions += 1 })
    XCTAssertTrue(unlocked.page.purchaseOffers.isEmpty)
    XCTAssertEqual(submissions, 0)
    let locked = page([offer()])
    let result = try await service.unlockFree(in: locked, load: { _ in locked }, submit: { _, _ in submissions += 1 })
    XCTAssertEqual(submissions, 1)
    XCTAssertNotNil(result.message)
    XCTAssertEqual(result.page.purchaseOffers.count, 1)
  }
  @MainActor func testConcurrentPurchaseIsRejected() async throws {
    let service = SouthPurchaseService()
    let locked = page([offer()])
    var tested = false
    _ = try await service.buy(offer(), page: locked, load: { _ in
      if !tested {
        tested = true
        do {
          _ = try await service.buy(self.offer(), page: locked, load: { _ in locked }, submit: { _, _ in XCTFail("Concurrent submission") })
          XCTFail("Expected busy")
        } catch { XCTAssertEqual(error as? SouthPurchaseIssue, .busy) }
      }
      return self.page([])
    }, submit: { _, _ in XCTFail("Already unlocked") })
    XCTAssertTrue(tested)
  }
  @MainActor func testGuestAndCancelledLoadsCannotSubmit() async throws {
    let service = SouthPurchaseService()
    var guest = page([offer()]); guest.loggedIn = false
    do {
      _ = try await service.buy(offer(), page: guest, load: { _ in guest }, submit: { _, _ in XCTFail("Guest submission") })
      XCTFail("Expected login failure")
    } catch { XCTAssertEqual(error as? ReaderFailure, .login) }
    do {
      _ = try await service.unlockFree(in: page([offer()]), load: { _ in throw CancellationError() }, submit: { _, _ in XCTFail("Cancelled submission") })
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  func testPurchaseInvalidatesOnlyTheAffectedThreadCache() {
    let cache = PageCache()
    let first = page([offer()])
    var second = first; second.url = SouthSitePolicy.pageURL(url, number: 2)!
    var other = first; other.url = URL(string: "https://south-plus.net/read.php?tid=21")!
    cache.store(first); cache.store(second); cache.store(other)
    cache.removeThread(url)
    XCTAssertNil(cache.value(for: first.url))
    XCTAssertNil(cache.value(for: second.url))
    XCTAssertNotNil(cache.value(for: other.url))
  }
  @MainActor func testSuppliedTwoFreeGateLayoutUnlocksBothDistinctPosts() async throws {
    // Reproduce the supplied 31-post table/body/footer structure with entirely
    // synthetic IDs, content and verification values. No live request is made.
    let source = (0...30).map { index in
      let pid = index == 0 ? "tpc" : String(9000 + index)
      let gate = index == 0 || index == 12 ? """
        <h6 class="quote jumbotron"><span class="s3">\(priceLabel) 0 \(currency), 10 buyers</span>
          <input type="button" onclick="location.href='job.php?action=buytopic&amp;tid=20&amp;pid=\(pid)&amp;verify=synthetic_token'"></h6>
        """ : "Reply content"
      return """
        <table class="js-post"><tr class="tr1"><th class="r_two" rowspan="2">
          <a href="u.php?action-show-uid-101.html"><strong>Author</strong></a></th><th class="r_one" id="td_\(pid)">
          <div class="tpc_content"><div id="p_\(pid)" class="c"></div><div class="f14" id="read_\(pid)">\(gate)</div></div>
        </th></tr><tr class="tr1 r_one"><th><div class="tpc_content"><div id="w_\(pid)" class="c"></div></div></th></tr></table>
        """
    }.joined()
    var current = try parse(source)
    XCTAssertEqual(current.posts.count, 31)
    XCTAssertEqual(current.purchaseOffers.map(\.postID), ["tpc", "9012"])
    XCTAssertTrue(current.purchaseOffers.allSatisfy(\.isFree))
    var submitted: [String] = []
    let result = try await SouthPurchaseService(pause: { _ in }).unlockFree(in: current, load: { _ in current }, submit: { selected, _ in
      submitted.append(selected.postID)
      let index = try XCTUnwrap(current.posts.firstIndex { $0.id == "post_" + selected.postID })
      current.posts[index].blocks = [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Unlocked content")])]
    })
    XCTAssertEqual(submitted, ["tpc", "9012"])
    XCTAssertTrue(result.page.purchaseOffers.isEmpty)
    XCTAssertEqual(result.page.posts.count, 31)
    XCTAssertNil(result.message)
  }

}
