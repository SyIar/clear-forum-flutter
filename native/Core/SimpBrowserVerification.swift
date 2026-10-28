import Foundation
import SwiftSoup

enum SimpBrowserVerification {
  static func required(_ source: String) throws -> Bool {
    try required(SwiftSoup.parse(source))
  }

  static func required(_ document: Document) throws -> Bool {
    // A quoted challenge inside an actual forum post is ordinary content.
    if try !document.select("article.message--post,.structItem--thread,.node--forum").isEmpty() { return false }
    let title = try document.title().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if title == "ddos-guard" || title.hasPrefix("ddos-guard |") { return true }
    if try !document.select("#ddg-l10n-title,#ddg-l10n-description,#ddg-img-loading").isEmpty() { return true }
    return try title.contains("just a moment") || title.contains("attention required") ||
      !document.select("#challenge-running,#challenge-form,.cf-turnstile").isEmpty()
  }

  static func canResume(expected: URL, actual: URL) -> Bool {
    guard SimpSitePolicy.readable(expected), SimpSitePolicy.readable(actual) else { return false }
    return SimpSitePolicy.pageCacheKey(expected) == SimpSitePolicy.pageCacheKey(actual)
  }
}
