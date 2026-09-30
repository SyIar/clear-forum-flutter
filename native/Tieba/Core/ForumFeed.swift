import Foundation

// A navigation destination owns this feed until it is popped. Page responses
// retain only display models, not the full protocol payload or decoded images.
struct ForumFeed {
  struct Page {
    let number: Int
    var items: [ThreadSummary]
    var hasMore: Bool
  }
  private(set) var pages: [Page] = []
  private(set) var pinned: [ThreadSummary] = []
  private(set) var forum: Forum?
  private(set) var currentPage = 1
  var items: [ThreadSummary] { pages.flatMap(\.items) }
  var nextPage: Int? { pages.last.flatMap { $0.hasMore ? $0.number + 1 : nil } }
  var previousPage: Int? { pages.first.flatMap { $0.number > 1 ? $0.number - 1 : nil } }
  var canGoForward: Bool { contains(currentPage + 1) || nextPage == currentPage + 1 }
  func contains(_ number: Int) -> Bool { pages.contains { $0.number == number } }
  func firstThread(on number: Int) -> String? { pages.first { $0.number == number }?.items.first?.id }
  mutating func showPage(_ number: Int) { if contains(number) { currentPage = number } }
  mutating func showThread(_ id: String) {
    if let page = pages.first(where: { $0.items.contains { $0.id == id } }) { currentPage = page.number }
  }
  mutating func markSigned() { forum?.signed = true }

  @discardableResult mutating func apply(_ response: PageResult<ThreadSummary>, replacingAll: Bool = false) -> Bool {
    guard response.page > 0 else { return false }
    // A late response must not introduce a gap into a continuous feed.
    guard replacingAll || pages.isEmpty || contains(response.page) || response.page == nextPage || response.page == previousPage else { return false }
    if replacingAll { self = ForumFeed() }
    if let forum = response.forum { self.forum = forum }
    var incomingPins = Set<String>()
    let freshPins = response.items.filter { $0.pinned && !$0.id.isEmpty && incomingPins.insert($0.id).inserted }
    // Page one is authoritative for removed pins; later pages may omit them.
    if response.page == 1 { pinned = freshPins }
    else {
      pinned = pinned.map { item in freshPins.first { $0.id == item.id } ?? item }
      let retainedIDs = Set(pinned.map(\.id))
      pinned.append(contentsOf: freshPins.filter { !retainedIDs.contains($0.id) })
    }
    let pinnedIDs = Set(pinned.map(\.id))
    for index in pages.indices { pages[index].items.removeAll { pinnedIDs.contains($0.id) } }
    // Keep a thread on its already loaded page when live reply sorting moves it
    // across a server page boundary. Its row identity and position stay stable.
    var seen = Set(pages.filter { $0.number != response.page }.flatMap(\.items).map(\.id)).union(pinnedIDs)
    let rows = response.items.filter { !$0.pinned && !$0.id.isEmpty && seen.insert($0.id).inserted }
    let page = Page(number: response.page, items: rows, hasMore: response.hasMore)
    if let index = pages.firstIndex(where: { $0.number == response.page }) { pages[index] = page }
    else { pages.append(page); pages.sort { $0.number < $1.number } }
    if !contains(currentPage) { currentPage = response.page }
    return true
  }
}

enum ForumFeedEdge { case previous, next }

// Layout changes and a cancelled interactive navigation transition must never
// trigger a request. One drag can request at most one adjacent page.
struct ForumFeedEdgeTrigger {
  private var fired = false
  mutating func beginDrag() { fired = false }
  mutating func update(topPull: Double, remaining: Double, interacting: Bool, previous: Bool, next: Bool) -> ForumFeedEdge? {
    guard interacting, !fired else { return nil }
    let edge: ForumFeedEdge?
    if topPull >= 56 && previous { edge = .previous }
    else if topPull <= 0 && remaining <= 240 && next { edge = .next }
    else { edge = nil }
    if edge != nil { fired = true }
    return edge
  }
}

struct ForumFeedRequest: Equatable {
  let id = UUID()
  var page = 1
  var replacingAll = true
  var moveToPage = true
}

// SwiftUI restarts .task when a covered destination appears again. A completed
// request (including an error) is retried only through an explicit new request.
struct ForumFeedLoadGate {
  private var completed: UUID?
  func needsLoad(_ request: ForumFeedRequest) -> Bool { completed != request.id }
  mutating func finish(_ request: ForumFeedRequest) { completed = request.id }
}
