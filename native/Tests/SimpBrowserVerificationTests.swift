import Foundation
import XCTest
@testable import ForumCore

final class SimpBrowserVerificationTests: XCTestCase {
  private let target = URL(string: "https://simpcity.cr/threads/example.123/page-48")!
  private let challenge = """
  <html><head><title>DDoS-Guard</title></head><body><div class="container">
  <h1 id="ddg-l10n-title">Checking your browser before accessing <span class="ddg-origin">simpcity.cr</span></h1>
  <p id="ddg-l10n-description">Please wait a few seconds.</p><img id="ddg-img-loading">
  </div></body></html>
  """

  func testChallengeIsVerificationRatherThanPermissionOrNetworkFailure() throws {
    for status in [200, 403, 503] {
      XCTAssertThrowsError(try ForumParser().parse(challenge, url: target, status: status)) {
        XCTAssertEqual($0 as? ReaderFailure, .verification)
      }
    }
  }

  func testRateLimitStillTakesPrecedence() {
    XCTAssertThrowsError(try ForumParser().parse(challenge, url: target, status: 429)) {
      XCTAssertEqual($0 as? ReaderFailure, .rateLimit)
    }
  }

  func testLocalizedOrMissingTitleStillUsesStructuralMarkers() throws {
    XCTAssertTrue(try SimpBrowserVerification.required(challenge.replacingOccurrences(of: "<title>DDoS-Guard</title>", with: "")))
    XCTAssertTrue(try SimpBrowserVerification.required("<title>DDoS-Guard</title><body>Please wait</body>"))
  }

  func testExistingCloudflareChecksRemainSupported() throws {
    XCTAssertTrue(try SimpBrowserVerification.required("<title>Just a moment...</title>"))
    XCTAssertTrue(try SimpBrowserVerification.required("<form id='challenge-form'></form>"))
  }

  func testQuotedChallengeIsNotAChallengePage() throws {
    let source = """
    <html data-template="thread_view"><title>Browser checks | SimpCity</title>
    <h1 class="p-title-value">Browser checks</h1>
    <article id="post-1" class="message--post"><div class="message-body"><div class="bbWrapper">
    <blockquote><h1 id="ddg-l10n-title">Checking your browser before accessing</h1></blockquote>
    </div></div></article></html>
    """
    XCTAssertFalse(try SimpBrowserVerification.required(source))
    XCTAssertEqual(try ForumParser().parse(source, url: target).posts.count, 1)
  }

  func testOrdinaryForbiddenAndUnsupportedPagesRemainDistinct() {
    for (status, expected) in [(403, ReaderFailure.forbidden), (200, .unsupported)] {
      XCTAssertThrowsError(try ForumParser().parse("<title>Access denied</title>", url: target, status: status)) {
        XCTAssertEqual($0 as? ReaderFailure, expected)
      }
    }
  }

  func testSearchChallengeDoesNotGetReportedAsAnInvalidSearchForm() {
    XCTAssertThrowsError(try SimpSearch.formBody(challenge, url: SimpSearch.formURL, status: 403, query: SimpSearchQuery(keywords: "example"))) {
      XCTAssertEqual($0 as? ReaderFailure, .verification)
    }
    XCTAssertThrowsError(try SimpSearch.parseResult(challenge, url: SimpSearch.submitURL, status: 503)) {
      XCTAssertEqual($0 as? ReaderFailure, .verification)
    }
  }

  func testAutomaticReturnRequiresTheRequestedPageAndOrigin() {
    XCTAssertTrue(SimpBrowserVerification.canResume(expected: target, actual: URL(string: target.absoluteString + "#post-99")!))
    for address in ["https://simpcity.cr/threads/example.123/page-49", "https://simpcity.cr/threads/another.456/page-48",
                    "https://simpcity.cr/login/", "https://example.com/threads/example.123/page-48", "http://simpcity.cr/threads/example.123/page-48"] {
      XCTAssertFalse(SimpBrowserVerification.canResume(expected: target, actual: URL(string: address)!))
    }
  }
}
