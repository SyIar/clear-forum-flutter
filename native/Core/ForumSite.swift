import Foundation

enum ForumSite: String, Codable, CaseIterable, Identifiable {
  case simp, south
  var id: String { rawValue }
  var title: String { self == .simp ? "SimpCity" : "South Plus" }
  var host: String { self == .simp ? SimpSitePolicy.host : SouthSitePolicy.host }
  var base: URL { self == .simp ? SimpSitePolicy.base : SouthSitePolicy.base }
  var start: URL { self == .simp ? base : SouthSitePolicy.start }
  var login: URL { self == .simp ? base.appendingPathComponent("login/") : SouthSitePolicy.login }
  var search: URL { base.appendingPathComponent(self == .simp ? "search/" : "search.php") }
  init?(url: URL) {
    guard let match = Self.allCases.first(where: { $0.sameOrigin(url) }) else { return nil }
    self = match
  }
  func sameOrigin(_ url: URL) -> Bool {
    self == .simp ? SimpSitePolicy.sameOrigin(url) : SouthSitePolicy.sameOrigin(url)
  }
  func accepts(_ url: URL) -> Bool {
    self == .simp ? SimpSitePolicy.readable(url) : SouthSitePolicy.readable(url)
  }
  func isLogin(_ url: URL) -> Bool {
    self == .simp ? sameOrigin(url) && url.path.hasPrefix("/login") : SouthSitePolicy.isLogin(url)
  }
  func domainMatches(_ cookie: HTTPCookie) -> Bool {
    self == .simp ? SimpSitePolicy.domainMatches(cookie) : SouthSitePolicy.domainMatches(cookie)
  }
  func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
    self == .simp ? SimpSitePolicy.matches(cookie, url: url) : SouthSitePolicy.matches(cookie, url: url)
  }
}
