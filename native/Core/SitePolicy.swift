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
  static func threadKey(_ url: URL) -> String? {
    guard readable(url) else { return nil }
    let parts = url.path.split(separator: "/")
    guard parts.count >= 2, parts[0] == "threads", let id = parts[1].split(separator: ".").last,
          !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return String(id)
  }
  static func threadRoot(_ url: URL) -> URL? {
    guard threadKey(url) != nil else { return nil }
    return base.appendingPathComponent("threads/\(url.path.split(separator: "/")[1])/")
  }
  static func pageNumber(_ url: URL) -> Int {
    if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value,
       let number = Int(value) { return number }
    if let last = url.path.split(separator: "/").last, last.hasPrefix("page-"), let number = Int(last.dropFirst(5)) { return number }
    return 1
  }
  static func pageRoot(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    var parts = url.path.split(separator: "/").map(String.init)
    if let last = parts.last, last.range(of: #"^page-\d+$"#, options: .regularExpression) != nil { parts.removeLast() }
    components.path = parts.isEmpty ? "/" : "/" + parts.joined(separator: "/") + "/"
    components.fragment = nil
    components.queryItems = components.queryItems?.filter { $0.name != "page" }
    if components.queryItems?.isEmpty == true { components.queryItems = nil }
    return components.url ?? url
  }
}


