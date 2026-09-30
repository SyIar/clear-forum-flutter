import Foundation

enum SouthSitePolicy {
  static let host = "south-plus.net"
  static let base = URL(string: "https://south-plus.net/")!
  static let start = URL(string: "https://south-plus.net/thread.php?fid-9.html")!
  static let login = base.appendingPathComponent("login.php")

  struct Route {
    var path: String
    var parameters: [String: String]
    var legacy: Bool
    var page: Int { Int(parameters["page"] ?? "1") ?? 1 }
    var resourceKey: String {
      var identity = parameters
      identity.removeValue(forKey: "page")
      if path == "/read.php" { identity.removeValue(forKey: "fid") }
      return path + "?" + identity.keys.sorted().map { "\($0)=\(identity[$0]!)" }.joined(separator: "&")
    }
  }

  static func sameOrigin(_ url: URL) -> Bool {
    url.scheme == "https" && url.host?.lowercased() == host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
  }
  static func isEmoticon(_ url: URL) -> Bool {
    sameOrigin(url) && url.standardized.path.hasPrefix("/images/post/smile/") &&
      ["gif", "png", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased())
  }
  static func route(_ url: URL) -> Route? {
    guard sameOrigin(url), url.absoluteString.utf8.count < 8192,
          ["", "/", "/index.php", "/thread.php", "/read.php", "/u.php"].contains(url.path) else { return nil }
    let path = ["", "/"].contains(url.path) ? "/index.php" : url.path
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
    var values: [String: String] = [:]
    let legacy = !query.isEmpty && !query.contains("=")
    if legacy {
      guard query.hasSuffix(".html") else { return nil }
      let tokens = query.dropLast(5).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
      guard tokens.count % 2 == 0 else { return nil }
      for index in stride(from: 0, to: tokens.count, by: 2) {
        guard values.updateValue(tokens[index + 1], forKey: tokens[index]) == nil else { return nil }
      }
    } else {
      for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
        guard let value = item.value, values.updateValue(value, forKey: item.name) == nil else { return nil }
      }
    }
    // fpage records the source directory page, not a thread filter. Later
    // directory pages attach their own positive page number to every title.
    if path == "/read.php" {
      if let fpage = values.removeValue(forKey: "fpage"),
         fpage.range(of: #"^(0|[1-9][0-9]{0,4})$"#, options: .regularExpression) == nil { return nil }
      if let toread = values.removeValue(forKey: "toread"), !toread.isEmpty { return nil }
    }
    let permitted: Set<String> = path == "/read.php" ? ["tid", "fid", "uid", "page"] : path == "/thread.php" ? ["fid", "page", "type"] : path == "/u.php" ? ["action", "uid", "page"] : []
    for (key, value) in values {
      if key == "action" {
        guard path == "/u.php", value == "topic" else { return nil }
        continue
      }
      guard permitted.contains(key), value.range(of: #"^(0|[1-9][0-9]{0,17})$"#, options: .regularExpression) != nil else { return nil }
      if key == "page", !(1...99_999).contains(Int(value) ?? 0) { return nil }
      if ["fid", "tid", "uid"].contains(key), value == "0" { return nil }
    }
    if path == "/thread.php" && values["fid"] == nil { return nil }
    if path == "/read.php" && values["tid"] == nil { return nil }
    if path == "/u.php" && (values["action"] != "topic" || values["uid"] == nil) { return nil }
    return Route(path: path, parameters: values, legacy: legacy)
  }
  static func readable(_ url: URL) -> Bool { route(url) != nil || SouthSearch.parameters(url) != nil }
  static func isLogin(_ url: URL) -> Bool { sameOrigin(url) && url.path == "/login.php" }
  static func isThread(_ url: URL) -> Bool { route(url)?.path == "/read.php" }
  static func canonicalThreadURL(_ url: URL) -> URL {
    guard let route = route(url), route.path == "/read.php",
          var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
    // Full threads use query syntax; author-filtered threads keep PHPWind's
    // legacy syntax. Both preserve page and fragment, excluding action URLs.
    let keys = ["tid", "fid", "uid", "page"].filter { route.parameters[$0] != nil }
    if route.parameters["uid"] != nil {
      parts.percentEncodedQuery = keys.map { "\($0)-\(route.parameters[$0]!)" }.joined(separator: "-") + ".html"
    } else {
      parts.queryItems = keys.map { URLQueryItem(name: $0, value: route.parameters[$0]) }
    }
    return parts.url ?? url
  }
  static func threadKey(_ url: URL) -> String? { isThread(url) ? route(url)?.parameters["tid"] : nil }
  static func authorID(_ url: URL) -> String? { isThread(url) ? route(url)?.parameters["uid"] : nil }
  static func topicAuthorID(_ url: URL) -> String? { route(url)?.path == "/u.php" ? route(url)?.parameters["uid"] : nil }
  static func validAuthorID(_ id: String) -> Bool { id.range(of: #"^[1-9][0-9]{0,17}$"#, options: .regularExpression) != nil }
  static func authorTopics(_ id: String) -> URL? {
    guard validAuthorID(id) else { return nil }
    return URL(string: "u.php?action-topic-uid-\(id).html", relativeTo: base)?.absoluteURL
  }
  static func threadRoot(_ url: URL) -> URL? {
    guard let id = threadKey(url) else { return nil }
    return URL(string: "read.php?tid=\(id)", relativeTo: base)?.absoluteURL
  }
  static func pageNumber(_ url: URL) -> Int { Int(SouthSearch.parameters(url)?["page"] ?? "") ?? route(url)?.page ?? 1 }
  static func pageRoot(_ url: URL) -> URL {
    if let search = SouthSearch.pageURL(url, number: 1) { return search }
    guard let route = route(url) else { return withoutFragment(url) }
    return URL(string: route.resourceKey, relativeTo: base)!.absoluteURL
  }
  static func pageURL(_ url: URL, number: Int) -> URL? {
    if let search = SouthSearch.pageURL(url, number: number) { return search }
    guard var route = route(url), route.path != "/index.php", (1...99_999).contains(number) else { return nil }
    route.parameters["page"] = number == 1 ? nil : String(number)
    var parts = URLComponents(url: base.appendingPathComponent(String(route.path.dropFirst())), resolvingAgainstBaseURL: false)!
    let keys = ["action", "fid", "tid", "uid", "type", "page"].filter { route.parameters[$0] != nil }
    if route.legacy { parts.percentEncodedQuery = keys.map { "\($0)-\(route.parameters[$0]!)" }.joined(separator: "-") + ".html" }
    else { parts.queryItems = keys.map { URLQueryItem(name: $0, value: route.parameters[$0]) } }
    return parts.url.map(canonicalThreadURL)
  }
  static func pageCacheKey(_ url: URL) -> String {
    if let search = SouthSearch.pageURL(url, number: pageNumber(url)) { return search.absoluteString }
    guard let route = route(url) else { return withoutFragment(url).absoluteString }
    return host + route.resourceKey + "&page=\(route.page)"
  }
  static func domainMatches(_ cookie: HTTPCookie) -> Bool {
    cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == host
  }
  static func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
    guard sameOrigin(url), domainMatches(cookie), cookie.expiresDate.map({ $0 > Date() }) ?? true else { return false }
    let path = url.path.isEmpty ? "/" : url.path
    return path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
  }
  static func resolve(_ value: String?, from page: URL, internalOnly: Bool = false) -> URL? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
          var candidate = URL(string: raw, relativeTo: page)?.absoluteURL else { return nil }
    if candidate.scheme == "http", candidate.host?.lowercased() == host, candidate.port == nil || candidate.port == 80 {
      var parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
      parts.scheme = "https"; parts.port = nil; candidate = parts.url ?? candidate
    }
    guard candidate.scheme == "https", !(candidate.host ?? "").isEmpty, candidate.user == nil, candidate.password == nil,
          candidate.port == nil || candidate.port == 443, candidate.absoluteString.utf8.count <= 8192 else { return nil }
    return internalOnly && !readable(candidate) ? nil : canonicalThreadURL(candidate)
  }
  static func withoutFragment(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    components.fragment = nil
    return components.url ?? url
  }
}
