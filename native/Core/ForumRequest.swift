import Foundation

enum ForumRequest {
  static func page(site: ForumSite, url: URL, userAgent: String, cookies: [HTTPCookie]) throws -> URLRequest {
    guard site.accepts(url), !userAgent.isEmpty else { throw ReaderFailure.unsupported }
    var request = URLRequest(url: SitePolicy.withoutFragment(url), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
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
