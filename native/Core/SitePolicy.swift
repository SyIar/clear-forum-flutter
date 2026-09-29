import Foundation

// Dispatch by the URL's origin, never by a mutable global selection.
enum SitePolicy {
  static let base = SimpSitePolicy.base
  static let host = SimpSitePolicy.host
  static func sameOrigin(_ url: URL) -> Bool { ForumSite(url: url) != nil }
  static func readable(_ url: URL) -> Bool { ForumSite(url: url)?.accepts(url) == true }
  static func domainMatches(_ cookie: HTTPCookie) -> Bool { ForumSite.allCases.contains { $0.domainMatches(cookie) } }
  static func matches(_ cookie: HTTPCookie, url: URL) -> Bool { ForumSite(url: url)?.matches(cookie, url: url) == true }
  static func threadKey(_ url: URL) -> String? {
    ForumSite(url: url) == .south ? SouthSitePolicy.threadKey(url) : SimpSitePolicy.threadKey(url)
  }
  static func threadRoot(_ url: URL) -> URL? {
    ForumSite(url: url) == .south ? SouthSitePolicy.threadRoot(url) : SimpSitePolicy.threadRoot(url)
  }
  static func pageNumber(_ url: URL) -> Int {
    ForumSite(url: url) == .south ? SouthSitePolicy.pageNumber(url) : SimpSitePolicy.pageNumber(url)
  }
  static func pageRoot(_ url: URL) -> URL {
    ForumSite(url: url) == .south ? SouthSitePolicy.pageRoot(url) : SimpSitePolicy.pageRoot(url)
  }
  static func pageURL(_ url: URL, number: Int) -> URL? {
    ForumSite(url: url) == .south ? SouthSitePolicy.pageURL(url, number: number) : SimpSitePolicy.pageURL(url, number: number)
  }
  static func pageCacheKey(_ url: URL) -> String {
    ForumSite(url: url) == .south ? SouthSitePolicy.pageCacheKey(url) : SimpSitePolicy.pageCacheKey(url)
  }
  static func resolve(_ value: String?, from page: URL, internalOnly: Bool = false) -> URL? {
    ForumSite(url: page) == .south
      ? SouthSitePolicy.resolve(value, from: page, internalOnly: internalOnly)
      : SimpSitePolicy.resolve(value, from: page, internalOnly: internalOnly)
  }
  static func withoutFragment(_ url: URL) -> URL { SimpSitePolicy.withoutFragment(url) }
}
