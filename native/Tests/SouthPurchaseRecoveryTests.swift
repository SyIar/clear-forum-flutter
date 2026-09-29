import Foundation
import XCTest
@testable import ForumCore

final class SouthPurchaseRecoveryTests: XCTestCase {
  private let url = URL(string: "https://south-plus.net/read.php?tid-20.html")!
  private func offer(_ price: Decimal = 0, pid: String = "tpc") -> SouthPurchaseOffer {
    SouthPurchaseOffer(threadID: "20", postID: pid, price: price,
      action: URL(string: "https://south-plus.net/job.php?action=buytopic&tid=20&pid=\(pid)&verify=synthetic")!)
  }
  private func page(_ offers: [SouthPurchaseOffer]) -> ForumPage {
    let posts = ["tpc", "123"].map { id in
      ForumPost(id: "post_" + id, author: "Author", date: "", number: "", blocks: offers.first(where: { $0.postID == id }).map {
        [BodyBlock(kind: .purchase, purchase: $0)]
      } ?? [BodyBlock(kind: .paragraph, runs: [TextRun(text: "Unlocked content")])])
    }
    return ForumPage(url: url, title: "Sample", kind: .posts, entries: [], posts: posts, pageNumber: 1, loggedIn: true)
  }
  @MainActor func testTransientPreflightAndConfirmationReadsRetryWithoutRepeatingPurchase() async throws {
    let locked = page([offer()])
    var reads = 0
    var submissions = 0
    var waits: [Int] = []
    let service = SouthPurchaseService(pause: { waits.append($0) })
    let result = try await service.unlockFree(in: locked, load: { _ in
      reads += 1
      if reads == 1 || reads == 3 { throw ReaderFailure.unsupported }
      return submissions == 0 ? locked : self.page([])
    }, submit: { _, _ in submissions += 1 })
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(submissions, 1)
    XCTAssertEqual(waits, [1, 1])
    XCTAssertNil(result.message)
    XCTAssertTrue(result.page.purchaseOffers.isEmpty)
  }
  @MainActor func testDelayedUnlockIsPolledUntilVisible() async throws {
    let locked = page([offer()])
    var reads = 0
    var submissions = 0
    let result = try await SouthPurchaseService(pause: { _ in }).buy(offer(), page: locked, load: { _ in
      reads += 1
      return reads < 4 ? locked : self.page([])
    }, submit: { _, _ in submissions += 1 })
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(submissions, 1)
    XCTAssertNil(result.message)
  }
  @MainActor func testLostPaidSubmissionResponseUsesReadOnlyReconciliation() async throws {
    let paid = offer(5)
    let locked = page([paid])
    var submitted = false
    var submissions = 0
    let result = try await SouthPurchaseService(pause: { _ in }).buy(paid, page: locked, load: { _ in
      submitted ? self.page([]) : locked
    }, submit: { _, _ in
      submissions += 1; submitted = true
      throw ReaderFailure.network
    })
    XCTAssertEqual(submissions, 1)
    XCTAssertNil(result.message)
    XCTAssertTrue(result.page.purchaseOffers.isEmpty)
  }
  @MainActor func testFailedPreflightStopsTheBatchWithPurchaseSpecificMessage() async throws {
    let locked = page([offer(), offer(0, pid: "123")])
    var reads = 0
    let result = try await SouthPurchaseService(pause: { _ in }).unlockFree(in: locked, load: { _ in
      reads += 1; throw ReaderFailure.unsupported
    }, submit: { _, _ in XCTFail("A failed preflight cannot submit") })
    XCTAssertEqual(reads, 3)
    XCTAssertEqual(result.page.purchaseOffers.count, 2)
    XCTAssertEqual(result.message, SouthPurchaseIssue.checkUnavailable.localizedDescription)
  }
  @MainActor func testFailedConfirmationPreservesPageAndNeverRepeatsPaidSubmission() async throws {
    let paid = offer(2)
    let locked = page([paid])
    var reads = 0
    var submissions = 0
    let result = try await SouthPurchaseService(pause: { _ in }).buy(paid, page: locked, load: { _ in
      reads += 1
      if reads > 1 { throw ReaderFailure.unsupported }
      return locked
    }, submit: { _, _ in submissions += 1 })
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(submissions, 1)
    XCTAssertEqual(result.page.purchaseOffers, [paid])
    XCTAssertEqual(result.message, SouthPurchaseIssue.confirmationUnavailable.localizedDescription)
  }
  @MainActor func testPersistentLockHasBoundedReadsAndOneSubmission() async throws {
    let locked = page([offer()])
    var reads = 0
    var submissions = 0
    let result = try await SouthPurchaseService(pause: { _ in }).unlockFree(in: locked, load: { _ in
      reads += 1; return locked
    }, submit: { _, _ in submissions += 1 })
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(submissions, 1)
    XCTAssertEqual(result.message, SouthPurchaseIssue.unconfirmed.localizedDescription)
  }
  @MainActor func testAuthenticationVerificationAndRateLimitErrorsAreNotRetried() async throws {
    for failure in [ReaderFailure.login, .verification, .forbidden, .rateLimit] {
      var reads = 0
      let result = try await SouthPurchaseService(pause: { _ in XCTFail("Must not retry") }).unlockFree(in: page([offer()]), load: { _ in
        reads += 1; throw failure
      }, submit: { _, _ in XCTFail("Must not submit") })
      XCTAssertEqual(reads, 1)
      XCTAssertEqual(result.message, failure.localizedDescription)
    }
  }
  @MainActor func testDifferentThreadPageOrAuthorFilterCannotConfirmPurchase() async throws {
    for address in ["https://south-plus.net/read.php?tid-21.html", "https://south-plus.net/read.php?tid-20-page-2.html", "https://south-plus.net/read.php?tid-20-uid-123.html"] {
      var redirected = page([]); redirected.url = URL(string: address)!
      var reads = 0
      let result = try await SouthPurchaseService(pause: { _ in XCTFail("Must not retry") }).unlockFree(in: page([offer()]), load: { _ in
        reads += 1; return redirected
      }, submit: { _, _ in XCTFail("Must not submit") })
      XCTAssertEqual(reads, 1)
      XCTAssertEqual(result.message, SouthPurchaseIssue.unexpectedPage.localizedDescription)
      XCTAssertEqual(result.page.url, url)
    }
  }
  @MainActor func testDisappearingTargetPostDoesNotCountAsConfirmed() async throws {
    let locked = page([offer()])
    var incomplete = page([]); incomplete.posts.removeFirst()
    var submitted = false
    let result = try await SouthPurchaseService(pause: { _ in }).buy(offer(), page: locked, load: { _ in
      submitted ? incomplete : locked
    }, submit: { _, _ in submitted = true })
    XCTAssertEqual(result.message, SouthPurchaseIssue.confirmationUnavailable.localizedDescription)
    XCTAssertEqual(result.page.posts.first?.id, "post_tpc")
    XCTAssertFalse(result.page.purchaseOffers.isEmpty)
  }
  @MainActor func testCancellationDuringBackoffDoesNotSubmitOrPublishAnError() async throws {
    let service = SouthPurchaseService(pause: { _ in throw CancellationError() })
    do {
      _ = try await service.unlockFree(in: page([offer()]), load: { _ in throw ReaderFailure.network }, submit: { _, _ in XCTFail("Cancelled") })
      XCTFail("Expected cancellation")
    } catch { XCTAssertTrue(error is CancellationError) }
  }
  @MainActor func testEachFreeUnlockIsPublishedBeforeTheNextPurchase() async throws {
    var current = page([offer(), offer(0, pid: "123")])
    var published: [Int] = []
    var submissions = 0
    let result = try await SouthPurchaseService(pause: { _ in }).unlockFree(in: current, load: { _ in current }, submit: { selected, _ in
      XCTAssertEqual(published.count, submissions)
      submissions += 1
      current = self.page(current.purchaseOffers.filter { $0.id != selected.id })
    }, onUpdate: { published.append($0.purchaseOffers.count) })
    XCTAssertEqual(published, [1, 0])
    XCTAssertNil(result.message)
  }
}
