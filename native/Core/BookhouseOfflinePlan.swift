import Foundation

struct BookhouseOfflinePlan: Codable, Equatable {
  let id: UUID
  let bookID: String
  private(set) var targets: [URL]
  private(set) var completed: Int
  var next: URL? { targets.indices.contains(completed) ? targets[completed] : nil }
  var valid: Bool {
    !bookID.isEmpty && !targets.isEmpty && (0...targets.count).contains(completed)
      && targets.allSatisfy { BookhouseSitePolicy.threadKey($0) != nil }
      && Set(targets.compactMap { BookhouseSitePolicy.threadKey($0) }).count == targets.count
  }
  init(bookID: String, chapters: [BookhouseChapter]) {
    id = UUID(); self.bookID = bookID; targets = []; completed = 0
    include(chapters)
  }
  mutating func include(_ chapters: [BookhouseChapter]) {
    var keys = Set(targets.compactMap { BookhouseSitePolicy.threadKey($0) })
    for chapter in chapters {
      guard let url = BookhouseSitePolicy.threadRoot(chapter.url), let key = BookhouseSitePolicy.threadKey(url), keys.insert(key).inserted else { continue }
      targets.append(url)
    }
  }
  mutating func advance(_ url: URL) {
    guard let next, BookhouseSitePolicy.threadKey(next) == BookhouseSitePolicy.threadKey(url) else { return }
    completed += 1
  }
  // A cache may have been cleared or evicted while this persisted task was paused.
  mutating func reconcile(contains: (URL) -> Bool) {
    if let missing = targets.prefix(completed).firstIndex(where: { !contains($0) }) { completed = missing }
  }
}

enum BookhouseOfflineFailure: Error { case capacity }
