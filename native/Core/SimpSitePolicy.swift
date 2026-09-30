import Foundation
enum SimpSitePolicy {
  static let host = "simpcity.cr"
  static func sameOrigin(_ url: URL) -> Bool {
    url.scheme == "https" && url.host?.lowercased() == host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
  }
  static func readable(_ url: URL) -> Bool {
    guard sameOrigin(url), !url.path.contains("%"), !url.path.contains("\\"), !url.path.components(separatedBy: "/").contains("..") else { return false }
    if searchResults(url) { return true }
    let pattern = #"^/(?:(?:forums|threads)/[^/]+\.\d+(?:/(?:page-\d+/?)?)?|posts/\d+/?|search-forums/[^/]+(?:/(?:page-\d+/?)?)?|whats-new/(?:posts/)?|watched/threads/?)$"#
    guard url.path == "/" || url.path.range(of: pattern, options: .regularExpression) != nil else { return false }
    var keys = Set<String>()
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
      guard keys.insert(item.name).inserted, let value = item.value else { return false }
      if item.name == "page" {
        guard value.range(of: #"^[1-9]\d{0,4}$"#, options: .regularExpression) != nil else { return false }
      } else if item.name == "order" {
        guard ["post_date", "last_post_date", "reaction_score"].contains(value) else { return false }
      } else if item.name == "prefix_id" || item.name.range(of: #"^prefix_id\[(?:[0-9]|1[0-5])\]$"#, options: .regularExpression) != nil {
        guard url.path.hasPrefix("/forums/"), value.range(of: #"^[1-9]\d{0,7}$"#, options: .regularExpression) != nil else { return false }
      } else { return false }
    }
    return true
  }
  static func searchResults(_ url: URL) -> Bool {
    guard sameOrigin(url), url.absoluteString.utf8.count <= 8192,
          url.path.range(of: #"^/search/[1-9][0-9]*/?$"#, options: .regularExpression) != nil else { return false }
    var keys = Set<String>()
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
      guard keys.insert(item.name).inserted, let value = item.value else { return false }
      switch item.name {
      case "page":
        guard value.range(of: #"^[1-9][0-9]{0,4}$"#, options: .regularExpression) != nil else { return false }
      case "q": guard value.utf8.count <= 1024 else { return false }
      case "o": guard ["date", "relevance"].contains(value) else { return false }
      case "c[title_only]": guard ["0", "1"].contains(value) else { return false }
      default: return false
      }
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
  static func pageURL(_ url: URL, number: Int) -> URL? {
    guard readable(url), (1...99_999).contains(number), !url.path.hasPrefix("/posts/") else { return nil }
    var components = URLComponents(url: pageRoot(url), resolvingAgainstBaseURL: false)!
    if number > 1 {
      if ["threads", "forums", "search-forums"].contains(url.path.split(separator: "/").first.map(String.init) ?? "") {
        components.path += "page-\(number)"
      } else {
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "page", value: String(number))]
      }
    }
    guard let result = components.url, readable(result) else { return nil }
    return result
  }
  static func pageCacheKey(_ url: URL) -> String {
    let canonical = pageURL(url, number: pageNumber(url)) ?? withoutFragment(url)
    var components = URLComponents(url: canonical, resolvingAgainstBaseURL: false)!
    components.queryItems = components.queryItems?.sorted { $0.name < $1.name }
    return components.url?.absoluteString ?? canonical.absoluteString
  }
}



extension SimpSitePolicy {
  static let base = URL(string: "https://simpcity.cr/")!
  static func resolve(_ value: String?, from page: URL, internalOnly: Bool = false) -> URL? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
          let candidate = URL(string: raw, relativeTo: page)?.absoluteURL,
          candidate.scheme == "https", !(candidate.host ?? "").isEmpty,
          candidate.user == nil, candidate.password == nil else { return nil }
    var resolved = candidate
    if sameOrigin(candidate), candidate.query == nil,
       let part = candidate.path.split(separator: "/").last,
       candidate.path.range(of: #"^/threads/[^/]+\.[0-9]+/post-[1-9][0-9]*/?$"#, options: .regularExpression) != nil {
      resolved = base.appendingPathComponent("posts/\(part.dropFirst(5))/")
    }
    if sameOrigin(candidate), candidate.path.range(of: #"^/threads/[^/]+\.\d+/unread/?$"#, options: .regularExpression) != nil,
       candidate.query == nil || candidate.query == "new=1" {
      var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
      components.path = candidate.path.replacingOccurrences(of: #"unread/?$"#, with: "", options: .regularExpression)
      components.query = nil
      resolved = components.url ?? candidate
    }
    return internalOnly && !readable(resolved) ? nil : resolved
  }
  // Browser navigation keeps normal requests intact, including unread routing.
  // Only a recognized redirect wrapper needs an app-level replacement.
  static func browserRedirectDestination(_ url: URL) -> URL? {
    guard sameOrigin(url), ["/redirect", "/redirect/"].contains(url.path) else { return nil }
    return linkDestination(url.absoluteString, from: base)
  }
  // Only user-tapped text/unfurl links use this. Authenticated requests and
  // automatic image/media loads must keep using resolve/readable instead.
  static func linkDestination(_ value: String?, from page: URL) -> URL? {
    func navigationURL(_ value: String?) -> URL? {
      guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw.utf8.count <= 8192,
            !raw.contains("\\"), raw.range(of: #"%(?![0-9A-Fa-f]{2})"#, options: .regularExpression) == nil,
            let candidate = URL(string: raw, relativeTo: page)?.absoluteURL,
            let scheme = candidate.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let targetHost = candidate.host, !targetHost.isEmpty,
            targetHost.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
            candidate.user == nil, candidate.password == nil,
            candidate.port.map({ (1...65535).contains($0) }) ?? true,
            var parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else { return nil }
      parts.scheme = scheme
      guard let url = parts.url else { return nil }
      if scheme == "https" { return resolve(url.absoluteString, from: page) }
      // Preserve external HTTP for explicit Safari navigation. Never downgrade
      // the forum origin, authenticated requests, or automatic resource loads.
      return targetHost.lowercased() == host ? nil : url
    }
    guard var target = navigationURL(value) else { return nil }
    func isWrapper(_ url: URL) -> Bool {
      sameOrigin(url) && ["/redirect", "/redirect/"].contains(url.path)
    }
    var seen = Set<String>()
    for _ in 0..<4 {
      guard isWrapper(target) else { return target }
      guard target.fragment == nil, seen.insert(target.absoluteString).inserted,
            let components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return nil }
      var fields: [String: String] = [:]
      for item in components.queryItems ?? [] {
        guard let value = item.value, fields.updateValue(value, forKey: item.name) == nil else { return nil }
      }
      // This is the observed Simp redirect contract, not a general URL decoder.
      guard Set(fields.keys) == Set(["to", "e", "m"]), fields["e"] == "1", fields["m"] == "b64",
            let encoded = fields["to"], !encoded.isEmpty, encoded.utf8.count <= 8192,
            encoded.range(of: #"^[A-Za-z0-9+/]+={0,2}$"#, options: .regularExpression) != nil else { return nil }
      let unpadded = encoded.replacingOccurrences(of: "=", with: "")
      guard unpadded.count % 4 != 1 else { return nil }
      let padded = unpadded + String(repeating: "=", count: (4 - unpadded.count % 4) % 4)
      guard !encoded.contains("=") || encoded == padded,
            let data = Data(base64Encoded: padded), data.base64EncodedString() == padded,
            let address = String(data: data, encoding: .utf8), !address.isEmpty,
            address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
            !address.contains("\\"),
            ["http", "https"].contains(URLComponents(string: address)?.scheme?.lowercased() ?? ""),
            let decoded = navigationURL(address), decoded.absoluteString.utf8.count <= 8192,
            !sameOrigin(decoded) || readable(decoded) || isWrapper(decoded) else { return nil }
      target = decoded
    }
    return isWrapper(target) ? nil : target
  }
  static func withoutFragment(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    components.fragment = nil
    return components.url ?? url
  }
}
