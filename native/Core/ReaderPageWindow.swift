import Foundation

enum ReaderEdge { case previous, next }

// Top navigation requires a deliberate pull. Forward navigation starts near
// the bottom during the user's drag or its deceleration, once per gesture.
struct ReaderEdgeTrigger {
  private var armed = false
  private var fired = false
  private var lastOffset = 0.0
  private var movingForward = false
  mutating func beginDrag(at offset: Double) {
    armed = true; fired = false; lastOffset = offset; movingForward = false
  }
  mutating func endDrag() { armed = false; movingForward = false }
  mutating func update(topPull: Double, remaining: Double, offset: Double,
                       interacting: Bool, decelerating: Bool = false,
                       previous: Bool, next: Bool) -> ReaderEdge? {
    guard armed, !fired, interacting || decelerating else { return nil }
    let delta = offset - lastOffset
    if interacting, delta > 0.5 { movingForward = true }
    else if delta < -0.5 { movingForward = false }
    lastOffset = offset
    let edge: ReaderEdge?
    if interacting, topPull >= 56, previous { edge = .previous }
    else if topPull <= 0, remaining <= 200, movingForward, next { edge = .next }
    else { edge = nil }
    if edge != nil { fired = true }
    return edge
  }
}

struct ReaderScrollMetrics {
  let offset: Double
  let topPull: Double
  let bottomPull: Double
  let remaining: Double
  init(contentOffset: Double, contentHeight: Double, viewportHeight: Double, topInset: Double, bottomInset: Double) {
    let start = -topInset
    let end = max(start, contentHeight - viewportHeight + bottomInset)
    offset = contentOffset - start
    topPull = max(0, start - contentOffset)
    bottomPull = max(0, contentOffset - end)
    remaining = max(0, end - contentOffset)
  }
}

struct ReaderPageWindow {
  private(set) var pages: [ForumPage] = []
  let countLimit: Int
  let costLimit: Int
  init(countLimit: Int = 5, costLimit: Int = 16 * 1024 * 1024) {
    self.countLimit = max(1, countLimit)
    self.costLimit = max(1, costLimit)
  }
  mutating func reset(_ page: ForumPage? = nil) { pages = page.map { [$0] } ?? [] }
  func page(for url: URL) -> ForumPage? {
    pages.first { SitePolicy.pageCacheKey($0.url) == SitePolicy.pageCacheKey(url) }
  }
  func page(containing id: String?) -> ForumPage? {
    guard let id else { return nil }
    if id == "top" || id == "south-pinned-more" { return pages.first }
    return pages.first { page in
      (id == "poll" && page.poll != nil) || page.posts.contains { $0.id == id } || page.entries.contains { $0.id == id }
    }
  }
  func page(offering offer: SouthPurchaseOffer) -> ForumPage? {
    pages.first { $0.purchaseOffers.contains { $0.id == offer.id } }
  }
  func target(_ edge: ReaderEdge) -> URL? {
    guard let boundary = edge == .previous ? pages.first : pages.last else { return nil }
    let number = boundary.pageNumber + (edge == .previous ? -1 : 1)
    guard (1...boundary.pageCount).contains(number), let expected = boundary.url(forPage: number) else { return nil }
    let linked = (edge == .previous ? boundary.previous : boundary.next) ?? expected
    guard SitePolicy.readable(linked), SitePolicy.pageCacheKey(linked) == SitePolicy.pageCacheKey(expected), page(for: linked) == nil else { return nil }
    return linked
  }
  @discardableResult mutating func insert(_ page: ForumPage, at edge: ReaderEdge, keeping current: URL) -> Bool {
    guard let expected = target(edge), page.kind == pages.first?.kind,
          page.pageNumber == SitePolicy.pageNumber(expected),
          SitePolicy.pageCacheKey(page.url) == SitePolicy.pageCacheKey(expected) else { return false }
    var incoming = page
    let oldPosts = Dictionary(pages.flatMap(\.posts).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let oldEntries = Dictionary(pages.flatMap(\.entries).map { (SitePolicy.pageCacheKey($0.url), $0) }, uniquingKeysWith: { first, _ in first })
    incoming.posts = incoming.posts.map { post in oldPosts[post.id].map { post.preservingBodyIdentity(from: $0) } ?? post }
    // Repeated sticky rows should not change identity when a URL alias is used.
    incoming.entries = incoming.entries.map { oldEntries[SitePolicy.pageCacheKey($0.url)] ?? $0 }
    if edge == .previous { pages.insert(incoming, at: 0) } else { pages.append(incoming) }
    trim(keeping: current)
    return true
  }
  mutating func replace(_ page: ForumPage) {
    guard let index = pages.firstIndex(where: { SitePolicy.pageCacheKey($0.url) == SitePolicy.pageCacheKey(page.url) }) else { return }
    pages[index] = page
  }
  mutating func trim(keeping current: URL) {
    var cost = pages.reduce(0) { $0 + $1.estimatedCacheCost }
    while pages.count > 1, pages.count > countLimit || cost > costLimit {
      let index = pages.firstIndex { SitePolicy.pageCacheKey($0.url) == SitePolicy.pageCacheKey(current) } ?? 0
      // Remove the farthest end, never the page the user is reading.
      let removed = index < pages.count / 2 ? pages.removeLast() : pages.removeFirst()
      cost -= removed.estimatedCacheCost
    }
  }
  func combined(active: ForumPage) -> ForumPage {
    guard !pages.isEmpty else { return active }
    var combined = active
    var posts = Set<String>()
    var entries = Set<String>()
    combined.posts = pages.flatMap(\.posts).filter { posts.insert($0.id).inserted }
    combined.entries = pages.flatMap(\.entries).filter { entries.insert(SitePolicy.pageCacheKey($0.url)).inserted }
    combined.poll = pages.compactMap(\.poll).first
    combined.totalPages = pages.map(\.pageCount).max()
    return combined
  }
}
