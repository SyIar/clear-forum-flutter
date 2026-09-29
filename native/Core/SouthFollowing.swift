import Foundation

struct SouthFollowedAuthor: Codable, Identifiable, Equatable {
  let id: String
  var name: String
  var avatar: URL?
  var followedAt: Date
  var topics: [SavedPage] = []
  var checkedAt: Date?
}

extension LibraryDocument {
  var following: [SouthFollowedAuthor] {
    guard site == .south else { return [] }
    return followedAuthors.values.filter { !blocksAuthor($0.id) }.sorted {
      $0.followedAt == $1.followedAt ? $0.id < $1.id : $0.followedAt > $1.followedAt
    }
  }
  var hasRefreshTargets: Bool { !trackedThreads.isEmpty || !following.isEmpty }
  func followsAuthor(_ id: String) -> Bool { site == .south && followedAuthors[id] != nil }
  mutating func followAuthor(id: String, name: String, avatar: URL? = nil, at date: Date = Date()) {
    guard site == .south, SouthSitePolicy.validAuthorID(id), !blocksAuthor(id) else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var author = followedAuthors[id] ?? SouthFollowedAuthor(id: id, name: "UID \(id)", followedAt: date)
    if !trimmed.isEmpty { author.name = String(trimmed.prefix(200)) }
    if let avatar = SouthSitePolicy.resolve(avatar?.absoluteString, from: site.base) { author.avatar = avatar }
    followedAuthors[id] = author
  }
  mutating func unfollowAuthor(_ id: String) { followedAuthors.removeValue(forKey: id) }
  func isUnreadSouthThread(_ url: URL) -> Bool {
    guard site == .south, site.accepts(url), let key = SitePolicy.threadKey(url) else { return false }
    return !readSouthThreads.contains(key)
  }
  // Only the author's first topics page represents their most recent topics.
  // A refresh records metadata, never a reading visit or a read baseline.
  @discardableResult
  mutating func updateFollowing(_ page: ForumPage, authorID: String, followedAt: Date, at date: Date = Date()) -> Bool {
    guard site == .south, page.kind == .threads, page.pageNumber == 1,
          SouthSitePolicy.topicAuthorID(page.url) == authorID,
          SouthSitePolicy.pageNumber(page.url) == 1, !blocksAuthor(authorID),
          var author = followedAuthors[authorID], author.followedAt == followedAt else { return false }
    var seen = Set<String>()
    let entries = page.entries.filter {
      guard $0.authorID == authorID, site.accepts($0.url), let key = SitePolicy.threadKey($0.url) else { return false }
      return seen.insert(key).inserted
    }
    guard page.entries.isEmpty || !entries.isEmpty else { return false }
    author.topics = entries.prefix(3).compactMap { entry in
      SitePolicy.threadRoot(entry.url).map { SavedPage(url: $0, title: entry.title) }
    }
    if let name = entries.first?.authorName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
      author.name = String(name.prefix(200))
    }
    author.checkedAt = date
    followedAuthors[authorID] = author
    for entry in entries.prefix(3) {
      mergePresentation(ThreadPresentation(thumbnail: entry.thumbnail, tags: entry.tags,
                                           authorID: authorID, authorName: entry.authorName ?? author.name), for: entry.url)
    }
    return true
  }
  mutating func pruneFollowing() {
    guard site == .south else { followedAuthors = [:]; readSouthThreads = []; return }
    followedAuthors = followedAuthors.filter { key, author in
      key == author.id && SouthSitePolicy.validAuthorID(key) && !blocksAuthor(key)
    }
    for id in Array(followedAuthors.keys) {
      guard var author = followedAuthors[id] else { continue }
      var seen = Set<String>()
      author.topics = Array(author.topics.filter {
        guard site.accepts($0.url), let key = SitePolicy.threadKey($0.url) else { return false }
        return seen.insert(key).inserted
      }.prefix(3))
      author.avatar = SouthSitePolicy.resolve(author.avatar?.absoluteString, from: site.base)
      followedAuthors[id] = author
    }
  }
}
