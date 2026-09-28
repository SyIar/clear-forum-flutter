import Foundation
enum SitePolicy {
  static let host = "simpcity.cr"
  static func sameOrigin(_ url: URL) -> Bool {
    url.scheme == "https" && url.host?.lowercased() == host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
  }
  static func readable(_ url: URL) -> Bool {
    guard sameOrigin(url), !url.path.contains("%"), !url.path.contains("\\"), !url.path.components(separatedBy: "/").contains("..") else { return false }
    let pattern = #"^/(?:(?:forums|threads)/[^/]+\.\d+(?:/(?:page-\d+/?)?)?|posts/\d+/?|search-forums/[^/]+(?:/(?:page-\d+/?)?)?|whats-new/(?:posts/)?|watched/threads/?)$"#
    guard url.path == "/" || url.path.range(of: pattern, options: .regularExpression) != nil else { return false }
    var keys = Set<String>()
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
      guard keys.insert(item.name).inserted, let value = item.value else { return false }
      if item.name == "page" {
        guard value.range(of: #"^[1-9]\d{0,4}$"#, options: .regularExpression) != nil else { return false }
      } else if item.name == "order" {
        guard ["post_date", "last_post_date", "reaction_score"].contains(value) else { return false }
      } else { return false }
    }
    return true
  }
  static func domainMatches(_ cookie: HTTPCookie) -> Bool {
    cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host
  }
  static func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
    guard sameOrigin(url), domainMatches(cookie), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
    let path = url.path.isEmpty ? "/" : url.path
    return path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
  }
}


