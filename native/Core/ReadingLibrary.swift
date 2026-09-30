import Foundation

struct SavedPage: Codable, Identifiable, Equatable {
  var id: String { url.absoluteString }
  var url: URL
  var title: String
  var titleIsCustom: Bool

  init(url: URL, title: String, titleIsCustom: Bool = false) {
    self.url = url
    self.title = title
    self.titleIsCustom = titleIsCustom
  }
  private enum CodingKeys: String, CodingKey { case url, title, titleIsCustom }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    url = try values.decode(URL.self, forKey: .url)
    title = try values.decode(String.self, forKey: .title)
    // Older libraries cannot distinguish an explicit label from a fetched one.
    // Preserve existing names; only known empty/path placeholders auto-update.
    // Foundation URL.path may omit the trailing slash retained by older labels.
    let alternatePath = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path + "/"
    let placeholders = [url.path, alternatePath, url.absoluteString]
    titleIsCustom = try values.decodeIfPresent(Bool.self, forKey: .titleIsCustom) ??
      (!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !placeholders.contains(title))
  }
}
struct ThreadPresentation: Codable, Equatable {
  var thumbnail: URL?
  var tags: [ForumTag] = []
  var authorID: String?
  var authorName: String?

  mutating func merge(_ incoming: ThreadPresentation) {
    if let thumbnail = incoming.thumbnail { self.thumbnail = thumbnail }
    if !incoming.tags.isEmpty { tags = incoming.tags }
    if let authorID = incoming.authorID { self.authorID = authorID }
    if let authorName = incoming.authorName { self.authorName = authorName }
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
  var blockedAuthors: [String: String] = [:]
  var followedAuthors: [String: SouthFollowedAuthor] = [:]
  var readSouthThreads: Set<String> = []
  static let key = "reading_library_v1"
  private enum CodingKeys: String, CodingKey {
    case site, version, bookmarks, recent, threads, presentations, blockedAuthors, followedAuthors, readSouthThreads
  }
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
    blockedAuthors = try values.decodeIfPresent([String: String].self, forKey: .blockedAuthors) ?? [:]
    followedAuthors = try values.decodeIfPresent([String: SouthFollowedAuthor].self, forKey: .followedAuthors) ?? [:]
    readSouthThreads = try values.decodeIfPresent(Set<String>.self, forKey: .readSouthThreads) ?? []
    if site == .south {
      readSouthThreads.formUnion(recent.compactMap { site.accepts($0.url) ? SitePolicy.threadKey($0.url) : nil })
      readSouthThreads.formUnion(threads.filter { $0.value.seenMaximum != nil }.keys)
    }
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
    document.blockedAuthors = site == .south ? document.blockedAuthors.filter { SouthSitePolicy.validAuthorID($0.key) } : [:]
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
    pruneFollowing()
    let keys = Set(trackedThreads.compactMap(SitePolicy.threadKey))
    threads = threads.filter { keys.contains($0.key) }
    let followedKeys = Set(followedAuthors.values.flatMap(\.topics).compactMap { SitePolicy.threadKey($0.url) })
    presentations = presentations.filter { keys.contains($0.key) || followedKeys.contains($0.key) }
  }
  mutating func capturePresentation(_ page: ForumPage) {
    guard site.accepts(page.url) else { return }
    captureFollowingNames(page)
    if page.kind == .posts { synchronizeTitle(page.title, for: page.url) }
    for entry in page.entries { synchronizeTitle(entry.title, for: entry.url) }
    if page.kind == .posts {
      let owner = site == .south ? page.posts.first(where: { $0.number == "#0" }) : nil
      mergePresentation(ThreadPresentation(thumbnail: page.thumbnail, tags: page.tags,
                                           authorID: owner?.authorID, authorName: owner?.authorID == nil ? nil : owner?.author), for: page.url)
    }
    for entry in page.entries {
      mergePresentation(ThreadPresentation(thumbnail: entry.thumbnail, tags: entry.tags,
                                           authorID: entry.authorID, authorName: entry.authorName), for: entry.url)
    }
  }
  mutating func mergePresentation(_ incoming: ThreadPresentation, for url: URL) {
    guard site.accepts(url), let key = SitePolicy.threadKey(url) else { return }
    let safe = ThreadPresentation(
      thumbnail: SitePolicy.resolve(incoming.thumbnail?.absoluteString, from: site.base),
      tags: incoming.tags.filter { site.accepts($0.url) },
      authorID: site == .south ? incoming.authorID.flatMap { SouthSitePolicy.validAuthorID($0) ? $0 : nil } : nil,
      authorName: site == .south ? incoming.authorName.flatMap { name in
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
      } : nil)
    guard safe.thumbnail != nil || !safe.tags.isEmpty || safe.authorID != nil || safe.authorName != nil else { return }
    presentations[key, default: ThreadPresentation()].merge(safe)
  }
  // Update the display title without moving saved page/floor destinations or
  // changing read/unread state. Slug aliases identify the same thread.
  mutating func synchronizeTitle(_ title: String, for url: URL) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard site.accepts(url), !trimmed.isEmpty else { return }
    func matches(_ saved: SavedPage) -> Bool {
      guard site.accepts(saved.url) else { return false }
      if let key = SitePolicy.threadKey(url) { return SitePolicy.threadKey(saved.url) == key }
      return SitePolicy.pageCacheKey(saved.url) == SitePolicy.pageCacheKey(url)
    }
    for index in bookmarks.indices where !bookmarks[index].titleIsCustom && matches(bookmarks[index]) { bookmarks[index].title = trimmed }
    for index in recent.indices where matches(recent[index]) { recent[index].title = trimmed }
  }
  mutating func remember(_ page: SavedPage) {
    guard site.accepts(page.url) else { return }
    if site == .south, let key = SitePolicy.threadKey(page.url) { readSouthThreads.insert(key) }
    recent.removeAll { Self.recentKey($0.url) == Self.recentKey(page.url) }
    recent.insert(page, at: 0)
    recent = Array(recent.prefix(10))
  }
  func subtitle(for page: SavedPage) -> String? {
    guard site == .south else { return page.url.path }
    guard site.accepts(page.url), let key = SitePolicy.threadKey(page.url) else { return nil }
    return presentations[key]?.authorName
  }
  mutating func toggle(_ page: SavedPage) {
    guard site.accepts(page.url) else { return }
    if bookmarks.contains(where: { $0.url == page.url }) { bookmarks.removeAll { $0.url == page.url } }
    else { bookmarks.append(page) }
  }
}
