import Foundation

enum BookhouseSitePolicy {
  static let host = "www.cool18.com"
  static let base = URL(string: "https://www.cool18.com/bbs4/")!
  static let start = base.appendingPathComponent("index.php")
  enum Kind { case catalog, cursor, thread, search, replies }
  struct Route {
    let kind: Kind
    let parameters: [String: String]
  }
  static func sameOrigin(_ url: URL) -> Bool {
    url.scheme == "https" && url.host?.lowercased() == host &&
      (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
  }
  static func validID(_ value: String?) -> Bool {
    value?.range(of: #"^[1-9][0-9]{0,17}$"#, options: .regularExpression) != nil
  }
  static func route(_ url: URL) -> Route? {
    guard sameOrigin(url), ["/bbs4/", "/bbs4/index.php"].contains(url.path), url.absoluteString.utf8.count < 8192 else { return nil }
    var parameters: [String: String] = [:]
    for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
      guard let value = item.value, parameters.updateValue(value, forKey: item.name) == nil else { return nil }
    }
    if parameters.isEmpty { return Route(kind: .catalog, parameters: [:]) }
    guard parameters["app"] == "forum", let action = parameters["act"] else { return nil }
    let kind: Kind
    let allowed: Set<String>
    switch action {
    case "threadview", "achildlist":
      guard validID(parameters["tid"]) else { return nil }
      kind = action == "threadview" ? .thread : .replies
      allowed = ["app", "act", "tid"]
    case "ajax":
      guard validID(parameters["mtid"]), parameters["aifilter"] == nil || parameters["aifilter"] == "0" else { return nil }
      kind = .cursor; allowed = ["app", "act", "mtid", "aifilter"]
    case "threadsearch":
      kind = .search
      allowed = ["app", "act", "action", "bbsdr", "keywords", "type", "uid", "p", "first", "submit"]
      guard parameters["action"] == nil || parameters["action"] == "search",
            parameters["bbsdr"] == nil || parameters["bbsdr"] == "bbs4",
            parameters["first"] == nil || parameters["first"] == "1",
            parameters["uid"] == nil || validID(parameters["uid"]),
            ["keywords", "type", "uid"].contains(where: { !(parameters[$0] ?? "").isEmpty }) else { return nil }
      if let page = parameters["p"], page.range(of: #"^(0|[1-9][0-9]{0,4})$"#, options: .regularExpression) == nil { return nil }
      for key in ["keywords", "type", "submit"] {
        if let value = parameters[key], value.count > 100 || value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return nil }
      }
    default: return nil
    }
    guard Set(parameters.keys).isSubset(of: allowed) else { return nil }
    return Route(kind: kind, parameters: parameters)
  }
  static func readable(_ url: URL) -> Bool { route(url) != nil }
  static func threadKey(_ url: URL) -> String? { route(url)?.kind == .thread ? route(url)?.parameters["tid"] : nil }
  static func thread(_ id: String) -> URL? {
    guard validID(id) else { return nil }
    return make(["app": "forum", "act": "threadview", "tid": id])
  }
  static func threadRoot(_ url: URL) -> URL? { threadKey(url).flatMap(thread) }
  static func replies(_ url: URL) -> URL? {
    guard let id = threadKey(url) else { return nil }
    return make(["app": "forum", "act": "achildlist", "tid": id])
  }
  static func cursor(_ id: String) -> URL? {
    guard validID(id) else { return nil }
    return make(["app": "forum", "act": "ajax", "mtid": id, "aifilter": "0"])
  }
  static func search(_ keywords: String) -> URL? {
    let text = keywords.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 100 else { return nil }
    let url = make(["app": "forum", "act": "threadsearch", "action": "search", "bbsdr": "bbs4", "keywords": text])
    return readable(url) ? url : nil
  }
  static func pageNumber(_ url: URL) -> Int { max(1, Int(route(url)?.parameters["p"] ?? "1") ?? 1) }
  static func pageURL(_ url: URL, number: Int) -> URL? {
    guard let route = route(url), route.kind == .search, (1...99_999).contains(number) else { return nil }
    var parameters = route.parameters
    parameters["p"] = number == 1 ? nil : String(number)
    return make(parameters)
  }
  static func pageRoot(_ url: URL) -> URL { pageURL(url, number: 1) ?? SitePolicy.withoutFragment(url) }
  static func pageCacheKey(_ url: URL) -> String {
    guard let route = route(url) else { return SitePolicy.withoutFragment(url).absoluteString }
    var values = route.parameters
    if route.kind == .search, pageNumber(url) == 1 { values.removeValue(forKey: "p") }
    return values.isEmpty ? start.absoluteString : make(values).absoluteString
  }
  static func resolve(_ value: String?, from page: URL, internalOnly: Bool = false) -> URL? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
          let source = URL(string: raw, relativeTo: page)?.absoluteURL,
          var parts = URLComponents(url: source, resolvingAgainstBaseURL: false) else { return nil }
    if [host, "cool18.com"].contains(parts.host?.lowercased() ?? ""), ["http", "https"].contains(parts.scheme ?? ""),
       parts.port == nil || parts.port == 80 || parts.port == 443 {
      parts.scheme = "https"; parts.host = host; parts.port = nil
    }
    guard let url = parts.url, url.scheme == "https", url.user == nil, url.password == nil,
          !(url.host ?? "").isEmpty, url.port == nil || url.port == 443, url.absoluteString.utf8.count < 8192,
          !internalOnly || readable(url) else { return nil }
    return url
  }
  private static func make(_ parameters: [String: String]) -> URL {
    var parts = URLComponents(url: start, resolvingAgainstBaseURL: false)!
    parts.queryItems = parameters.keys.sorted().map { URLQueryItem(name: $0, value: parameters[$0]) }
    return parts.url!
  }
}
