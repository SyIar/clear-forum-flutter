import Foundation

enum ForumSite: String, Codable, CaseIterable, Identifiable {
  case simp, south, bookhouse
  var id: String { rawValue }
  var title: String { self == .bookhouse ? AppText.text("Forbidden Library") : self == .simp ? "SimpCity" : "South Plus" }
  var host: String { self == .bookhouse ? BookhouseSitePolicy.host : self == .simp ? SimpSitePolicy.host : SouthSitePolicy.host }
  var base: URL { self == .bookhouse ? BookhouseSitePolicy.base : self == .simp ? SimpSitePolicy.base : SouthSitePolicy.base }
  var start: URL { self == .bookhouse ? BookhouseSitePolicy.start : self == .simp ? base : SouthSitePolicy.start }
  var supportsLogin: Bool { self != .bookhouse }
  var supportsThreadUpdates: Bool { self != .bookhouse }
  var login: URL { self == .bookhouse ? start : self == .simp ? base.appendingPathComponent("login/") : SouthSitePolicy.login }
  var search: URL { self == .bookhouse ? start : base.appendingPathComponent(self == .simp ? "search/" : "search.php") }
  init?(url: URL) {
    guard let match = Self.allCases.first(where: { $0.sameOrigin(url) }) else { return nil }
    self = match
  }
  func sameOrigin(_ url: URL) -> Bool {
    self == .bookhouse ? BookhouseSitePolicy.sameOrigin(url) : self == .simp ? SimpSitePolicy.sameOrigin(url) : SouthSitePolicy.sameOrigin(url)
  }
  func accepts(_ url: URL) -> Bool {
    self == .bookhouse ? BookhouseSitePolicy.readable(url) : self == .simp ? SimpSitePolicy.readable(url) : SouthSitePolicy.readable(url)
  }
  func isLogin(_ url: URL) -> Bool {
    supportsLogin && (self == .simp ? sameOrigin(url) && url.path.hasPrefix("/login") : SouthSitePolicy.isLogin(url))
  }
  func domainMatches(_ cookie: HTTPCookie) -> Bool {
    supportsLogin && (self == .simp ? SimpSitePolicy.domainMatches(cookie) : SouthSitePolicy.domainMatches(cookie))
  }
  func matches(_ cookie: HTTPCookie, url: URL) -> Bool {
    supportsLogin && (self == .simp ? SimpSitePolicy.matches(cookie, url: url) : SouthSitePolicy.matches(cookie, url: url))
  }
}
