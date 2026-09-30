import Foundation

enum ForumRequest {
  static func redirect(_ location: String?, from current: URL) -> URL? {
    guard let next = SitePolicy.resolve(location, from: current),
          var components = URLComponents(url: next, resolvingAgainstBaseURL: false) else { return nil }
    if components.fragment == nil { components.fragment = current.fragment }
    return components.url
  }
  static func page(site: ForumSite, url: URL, userAgent: String, cookies: [HTTPCookie]) throws -> URLRequest {
    guard site.accepts(url), !userAgent.isEmpty else { throw ReaderFailure.unsupported }
    let target = SouthSitePolicy.canonicalThreadURL(url)
    var request = URLRequest(url: SitePolicy.withoutFragment(target), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
    request.httpShouldHandleCookies = false
    request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    let applicable = cookies.filter { site.matches($0, url: url) }.sorted { $0.path.count > $1.path.count }
    if !applicable.isEmpty {
      for (key, value) in HTTPCookie.requestHeaderFields(with: applicable) { request.setValue(value, forHTTPHeaderField: key) }
    }
    return request
  }
}
