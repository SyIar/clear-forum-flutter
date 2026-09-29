import Foundation

struct SavedPage: Codable, Identifiable, Equatable {
  var id: String { url.absoluteString }
  var url: URL
  var title: String
}
struct ThreadPresentation: Codable, Equatable {
  var thumbnail: URL?
  var tags: [ForumTag] = []

  mutating func merge(_ incoming: ThreadPresentation) {
    if let thumbnail = incoming.thumbnail { self.thumbnail = thumbnail }
    if !incoming.tags.isEmpty { tags = incoming.tags }
  }
}
struct ThreadReadState: Codable, Equatable {
  var seenMaximum: Int?
  var latestMaximum: Int?
  var checkedAt: Date?
  var updated: Bool {
    guard let seenMaximum, let latestMaximum else { return false }
    return latestMaximum > seenMaximum
  }
  mutating func opened(maximum: Int, at date: Date = Date()) {
    guard maximum >= 0 else { return }
    seenMaximum = maximum
    checked(maximum: maximum, at: date)
  }
  mutating func checked(maximum: Int, at date: Date = Date()) {
    guard maximum >= 0 else { return }
    latestMaximum = maximum
    checkedAt = date
  }
}
struct LibraryDocument: Codable {
  var version = 1
  var site: ForumSite = .simp
  var bookmarks: [SavedPage] = []
  var recent: [SavedPage] = []
  var threads: [String: ThreadReadState] = [:]
  var presentations: [String: ThreadPresentation] = [:]
  static let key = "reading_library_v1"
  private enum CodingKeys: String, CodingKey { case site, version, bookmarks, recent, threads, presentations }
  init(site: ForumSite = .simp) { self.site = site }
  static func key(for site: ForumSite) -> String { site == .simp ? key : "south_reading_library_v1" }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    site = try values.decodeIfPresent(ForumSite.self, forKey: .site) ?? .simp
    version = try values.decode(Int.self, forKey: .version)
    bookmarks = try values.decode([SavedPage].self, forKey: .bookmarks)
    recent = try values.decode([SavedPage].self, forKey: .recent)
    threads = try values.decodeIfPresent([String: ThreadReadState].self, forKey: .threads) ?? [:]
    presentations = try values.decodeIfPresent([String: ThreadPresentation].self, forKey: .presentations) ?? [:]
  }
  static func load(from defaults: UserDefaults, site: ForumSite = .simp) throws -> LibraryDocument {
    let storageKey = key(for: site)
    let legacy = site == .simp ? defaults.string(forKey: "flutter." + key) : nil
    guard let raw = defaults.string(forKey: storageKey) ?? legacy else { return LibraryDocument(site: site) }
    guard let data = raw.data(using: .utf8), var document = try? JSONDecoder().decode(Self.self, from: data), document.version == 1, document.site == site else { throw ReaderFailure.storage }
    func unique(_ entries: [SavedPage], key: (URL) -> String) -> [SavedPage] {
      var seen = Set<String>()
      return entries.filter { site.accepts($0.url) && seen.insert(key($0.url)).inserted }
    }
    document.bookmarks = unique(document.bookmarks) { $0.absoluteString }
    document.recent = Array(unique(document.recent, key: recentKey).prefix(10))
    document.pruneTracking()
    return document
  }
  func save(to defaults: UserDefaults) throws {
    let data = try JSONEncoder().encode(self)
    defaults.set(String(decoding: data, as: UTF8.self), forKey: Self.key(for: site))
  }
  static func recentKey(_ url: URL) -> String {
    if let key = SitePolicy.threadKey(url) { return "\(ForumSite(url: url)?.rawValue ?? "unknown"):thread:\(key)" }
    return SitePolicy.withoutFragment(url).absoluteString
  }
  var trackedThreads: [URL] {
    var seen = Set<String>()
    return (recent + bookmarks).compactMap { page in
      guard site.accepts(page.url), let key = SitePolicy.threadKey(page.url), seen.insert(key).inserted else { return nil }
      return SitePolicy.threadRoot(page.url)
    }
  }
  mutating func pruneTracking() {
    let keys = Set(trackedThreads.compactMap(SitePolicy.threadKey))
    threads = threads.filter { keys.contains($0.key) }
    presentations = presentations.filter { keys.contains($0.key) }
  }
  mutating func capturePresentation(_ page: ForumPage) {
    guard site.accepts(page.url) else { return }
    if page.kind == .posts {
      mergePresentation(ThreadPresentation(thumbnail: page.thumbnail, tags: page.tags), for: page.url)
    }
    for entry in page.entries {
      mergePresentation(ThreadPresentation(thumbnail: entry.thumbnail, tags: entry.tags), for: entry.url)
    }
  }
  mutating func mergePresentation(_ incoming: ThreadPresentation, for url: URL) {
    guard site.accepts(url), let key = SitePolicy.threadKey(url) else { return }
    let safe = ThreadPresentation(
      thumbnail: SitePolicy.resolve(incoming.thumbnail?.absoluteString, from: site.base),
      tags: incoming.tags.filter { site.accepts($0.url) })
    guard safe.thumbnail != nil || !safe.tags.isEmpty else { return }
    presentations[key, default: ThreadPresentation()].merge(safe)
  }
  mutating func remember(_ page: SavedPage) {
    guard site.accepts(page.url) else { return }
    recent.removeAll { Self.recentKey($0.url) == Self.recentKey(page.url) }
    recent.insert(page, at: 0)
    recent = Array(recent.prefix(10))
  }
  mutating func toggle(_ page: SavedPage) {
    guard site.accepts(page.url) else { return }
    if bookmarks.contains(where: { $0.url == page.url }) { bookmarks.removeAll { $0.url == page.url } }
    else { bookmarks.append(page) }
  }
}
