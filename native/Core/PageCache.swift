import Foundation

struct CachedPage {
  var page: ForumPage
  var visibleID: String?
}

// Bounded LRU snapshots, not persisted HTML or retained view controllers.
// Cost is an estimate for parsed text/metadata, not the app's total resident memory.
final class PageCache {
  private struct Entry { var snapshot: CachedPage; let cost: Int }
  private var entries: [String: Entry] = [:]
  private var order: [String] = []
  let countLimit: Int
  let costLimit: Int
  private(set) var totalCost = 0
  var count: Int { entries.count }
  init(countLimit: Int = 20, costLimit: Int = 16 * 1024 * 1024) {
    self.countLimit = max(0, countLimit)
    self.costLimit = max(0, costLimit)
  }
  func value(for url: URL) -> CachedPage? {
    let key = SitePolicy.pageCacheKey(url)
    guard var snapshot = entries[key]?.snapshot else { return nil }
    touch(key)
    var location = URLComponents(url: snapshot.page.url, resolvingAgainstBaseURL: false)!
    location.fragment = url.fragment
    snapshot.page.url = location.url ?? snapshot.page.url
    return snapshot
  }
  func store(_ page: ForumPage, cost: Int? = nil) {
    let key = SitePolicy.pageCacheKey(page.url)
    let previousPosition = entries[key]?.snapshot.visibleID
    remove(key)
    let cost = max(1, cost ?? page.estimatedCacheCost)
    guard countLimit > 0, cost <= costLimit else { return }
    entries[key] = Entry(snapshot: CachedPage(page: page, visibleID: previousPosition), cost: cost)
    totalCost += cost
    touch(key)
    while entries.count > countLimit || totalCost > costLimit {
      guard let oldest = order.first else { break }
      remove(oldest)
    }
  }
  func savePosition(_ id: String?, for url: URL) {
    guard let id else { return }
    entries[SitePolicy.pageCacheKey(url)]?.snapshot.visibleID = id
  }
  func removeAll() { entries.removeAll(); order.removeAll(); totalCost = 0 }
  private func touch(_ key: String) { order.removeAll { $0 == key }; order.append(key) }
  private func remove(_ key: String) {
    if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
    order.removeAll { $0 == key }
  }
}

private extension ForumPage {
  var estimatedCacheCost: Int {
    func string(_ value: String) -> Int { value.utf8.count * 2 + 64 }
    func link(_ value: URL?) -> Int { value.map { string($0.absoluteString) } ?? 0 }
    func tags(_ values: [ForumTag]) -> Int { values.reduce(0) { $0 + string($1.title) + link($1.url) + 128 } }
    func block(_ value: BodyBlock) -> Int {
      var cost = 256 + string(value.label) + link(value.url) + link(value.poster)
      for run in value.runs { cost += string(run.text) + link(run.url) + 96 }
      for child in value.children { cost += block(child) }
      return cost
    }
    var cost = 2048 + string(title) + link(url) + link(thumbnail) + tags(self.tags)
    for entry in entries + breadcrumbs {
      cost += 256 + string(entry.title) + string(entry.subtitle) + link(entry.url) + link(entry.thumbnail) + tags(entry.tags)
    }
    for post in posts {
      cost += 256 + string(post.id) + string(post.author) + string(post.date)
      for body in post.blocks { cost += block(body) }
    }
    return cost
  }
}
