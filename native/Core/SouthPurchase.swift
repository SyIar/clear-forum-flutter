import Foundation
import SwiftSoup

struct SouthPurchaseOffer: Identifiable, Equatable {
  let threadID: String
  let postID: String
  let price: Decimal
  let action: URL
  var id: String { threadID + ":" + postID }
  var isFree: Bool { price == 0 }
  var priceText: String { NSDecimalNumber(decimal: price).stringValue }
}

enum SouthPurchaseIssue: String, Error, LocalizedError {
  case busy, changedPrice, unconfirmed
  var errorDescription: String? {
    switch self {
    case .busy: return "A purchase is already in progress."
    case .changedPrice: return "The price has changed. Check the updated price before buying."
    case .unconfirmed: return "The content is still locked. Open Site browser to check your balance or the site's message."
    }
  }
}

enum SouthPurchase {
  static func offer(_ node: Element, page: URL) -> SouthPurchaseOffer? {
    guard node.tagName() == "h6", node.hasClass("quote"), node.hasClass("jumbotron"), SouthSitePolicy.isThread(page),
          !node.parents().contains(where: { $0.tagName() == "blockquote" || $0.hasClass("blockquote") }),
          let body = node.parents().first(where: { $0.id().hasPrefix("read_") }),
          let threadID = SouthSitePolicy.threadKey(page),
          let label = try? node.select("span.s3").first()?.text(),
          let amount = capture(label, #"^\s*\u6b64\u5e16\u552e\u4ef7\s*([0-9]{1,8}(?:\.[0-9]{1,2})?)\s*SP\u5e01(?:\s*[,\uFF0C].*)?\s*$"#),
          let price = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
    let buttons = (try? node.select("input[type=button][onclick]").array()) ?? []
    guard buttons.count == 1, let script = try? buttons[0].attr("onclick"),
          let address = capture(script, #"^\s*(?:window\.)?location\.href\s*=\s*(['"])([^'"]+)\1\s*;?\s*$"#, group: 2),
          let action = SouthSitePolicy.resolve(address, from: page) else { return nil }
    let offer = SouthPurchaseOffer(threadID: threadID, postID: String(body.id().dropFirst(5)), price: price, action: action)
    return valid(offer, page: page) ? offer : nil
  }
  static func valid(_ offer: SouthPurchaseOffer, page: URL) -> Bool {
    guard SouthSitePolicy.isThread(page), SouthSitePolicy.threadKey(page) == offer.threadID,
          offer.price >= 0, offer.price <= 99_999_999,
          SouthSitePolicy.sameOrigin(offer.action), offer.action.path == "/job.php", offer.action.fragment == nil,
          offer.action.absoluteString.utf8.count <= 4096,
          offer.postID == "tpc" || capture(offer.postID, #"^([1-9][0-9]{0,17})$"#) != nil else { return false }
    var values: [String: String] = [:]
    for item in URLComponents(url: offer.action, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
      guard let value = item.value, values.updateValue(value, forKey: item.name) == nil else { return false }
    }
    return Set(values.keys) == ["action", "tid", "pid", "verify"] && values["action"] == "buytopic" &&
      values["tid"] == offer.threadID && values["pid"] == offer.postID &&
      capture(values["verify"] ?? "", #"^([A-Za-z0-9_-]{1,256})$"#) != nil
  }
  static func request(_ offer: SouthPurchaseOffer, page: URL, userAgent: String, cookies: [HTTPCookie]) throws -> URLRequest {
    guard valid(offer, page: page), !userAgent.isEmpty else { throw ReaderFailure.unsupported }
    var request = URLRequest(url: offer.action, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.httpShouldHandleCookies = false
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue(SitePolicy.withoutFragment(page).absoluteString, forHTTPHeaderField: "Referer")
    let applicable = cookies.filter { SouthSitePolicy.matches($0, url: offer.action) }.sorted { $0.path.count > $1.path.count }
    for (key, value) in HTTPCookie.requestHeaderFields(with: applicable) { request.setValue(value, forHTTPHeaderField: key) }
    return request
  }
  private static func capture(_ text: String, _ pattern: String, group: Int = 1) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: group), in: text) else { return nil }
    return String(text[range])
  }
}

extension ForumPage {
  var purchaseOffers: [SouthPurchaseOffer] {
    func collect(_ blocks: [BodyBlock]) -> [SouthPurchaseOffer] {
      blocks.flatMap { block in block.purchase.map { [$0] } ?? collect(block.children) }
    }
    var seen = Set<String>()
    return posts.flatMap { collect($0.blocks) }.filter { seen.insert($0.id).inserted }
  }
}

struct SouthPurchaseResult {
  var page: ForumPage
  var message: String?
}

// Only the visible reader calls this service; background update checks stay read-only.
@MainActor
final class SouthPurchaseService {
  typealias Load = (URL) async throws -> ForumPage
  typealias Submit = (SouthPurchaseOffer, URL) async throws -> Void
  private var busy = false

  func buy(_ offer: SouthPurchaseOffer, page: ForumPage, load: Load, submit: Submit) async throws -> SouthPurchaseResult {
    guard !busy else { throw SouthPurchaseIssue.busy }
    busy = true
    defer { busy = false }
    return try await perform(offer, page: page, load: load, submit: submit)
  }
  func unlockFree(in page: ForumPage, load: Load, submit: Submit) async throws -> SouthPurchaseResult {
    guard !busy else { throw SouthPurchaseIssue.busy }
    busy = true
    defer { busy = false }
    var result = SouthPurchaseResult(page: page)
    var attempted = Set<String>()
    while let offer = result.page.purchaseOffers.first(where: { $0.isFree && !attempted.contains($0.id) }) {
      guard attempted.count < 100 else { break }
      attempted.insert(offer.id)
      do {
        let next = try await perform(offer, page: result.page, load: load, submit: submit)
        result.page = next.page
        if let message = next.message { result.message = message }
      } catch is CancellationError { throw CancellationError() }
      catch { try Task.checkCancellation(); result.message = error.localizedDescription }
    }
    return result
  }
  private func perform(_ accepted: SouthPurchaseOffer, page: ForumPage, load: Load, submit: Submit) async throws -> SouthPurchaseResult {
    guard SouthPurchase.valid(accepted, page: page.url) else { throw ReaderFailure.unsupported }
    try Task.checkCancellation()
    let fresh = try await load(page.url)
    guard SitePolicy.pageCacheKey(fresh.url) == SitePolicy.pageCacheKey(page.url) else { throw ReaderFailure.unsupported }
    if fresh.loggedIn == false { throw ReaderFailure.login }
    guard let offer = fresh.purchaseOffers.first(where: { $0.id == accepted.id }) else { return SouthPurchaseResult(page: fresh) }
    guard offer.price == accepted.price else {
      return SouthPurchaseResult(page: fresh, message: SouthPurchaseIssue.changedPrice.localizedDescription)
    }
    try Task.checkCancellation()
    try await submit(offer, fresh.url)
    try Task.checkCancellation()
    let refreshed = try await load(fresh.url)
    guard SitePolicy.pageCacheKey(refreshed.url) == SitePolicy.pageCacheKey(fresh.url) else { throw ReaderFailure.unsupported }
    let stillLocked = refreshed.purchaseOffers.contains { $0.id == offer.id }
    return SouthPurchaseResult(page: refreshed, message: stillLocked ? SouthPurchaseIssue.unconfirmed.localizedDescription : nil)
  }
}
