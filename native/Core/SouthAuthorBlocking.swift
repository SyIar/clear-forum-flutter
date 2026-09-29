import Foundation

extension LibraryDocument {
  var blockedAuthorIDs: Set<String> { site == .south ? Set(blockedAuthors.keys) : [] }
  func blocksAuthor(_ id: String?) -> Bool { site == .south && id.map { blockedAuthors[$0] != nil } == true }
  mutating func blockAuthor(id: String, name: String) {
    guard site == .south, SouthSitePolicy.validAuthorID(id) else { return }
    blockedAuthors[id] = name.isEmpty ? "UID \(id)" : name
  }
  mutating func unblockAuthor(_ id: String) { blockedAuthors.removeValue(forKey: id) }
  func hidesSavedPage(_ page: SavedPage) -> Bool {
    guard site == .south, site.accepts(page.url) else { return false }
    if let author = SouthSitePolicy.topicAuthorID(page.url) ?? SouthSitePolicy.authorID(page.url), blocksAuthor(author) { return true }
    return SitePolicy.threadKey(page.url).map { blocksAuthor(presentations[$0]?.authorID) } ?? false
  }
  func visibleContent(in page: ForumPage) -> ForumPage {
    guard site == .south, site.accepts(page.url), !blockedAuthors.isEmpty else { return page }
    var visible = page
    visible.posts = page.posts.filter { !blocksAuthor($0.authorID) }
    visible.entries = page.entries.filter { entry in
      let owner = entry.authorID ?? SitePolicy.threadKey(entry.url).flatMap { presentations[$0]?.authorID }
      return !blocksAuthor(owner)
    }
    if page.posts.contains(where: { $0.number == "#0" && blocksAuthor($0.authorID) }) { visible.poll = nil }
    return visible
  }
}
