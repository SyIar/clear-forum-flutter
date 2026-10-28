import Foundation

// Own every disk mutation on one executor, including queue checkpoints and cache eviction.
actor BookhouseOfflineRepository {
  struct Snapshot {
    let revision: Int
    let entries: [BookhouseOfflineCache.Entry]
    let plans: [BookhouseOfflinePlan]
    let bytes: Int
    let limit: Int
  }
  private let supportDirectory: URL?
  private let initialLimit: Int
  private var cache: BookhouseOfflineCache?
  private var plans: [BookhouseOfflinePlan] = []
  private var plansURL: URL?
  private var revision = 0

  // Initialization itself performs no IO, so the main actor can construct this safely.
  init(supportDirectory: URL? = nil, limit: Int) {
    self.supportDirectory = supportDirectory; initialLimit = limit
  }
  private func open() throws -> BookhouseOfflineCache {
    if let cache { return cache }
    let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true)
    var directory = support.appendingPathComponent("OfflineBooks", isDirectory: true)
    let tasks = support.appendingPathComponent("OfflineBookTasks.json")
    let restored = FileManager.default.fileExists(atPath: tasks.path)
      ? try JSONDecoder().decode([BookhouseOfflinePlan].self, from: Data(contentsOf: tasks)) : []
    guard restored.allSatisfy(\.valid), Set(restored.map(\.bookID)).count == restored.count else { throw ReaderFailure.storage }
    let opened = try BookhouseOfflineCache(directory: directory, limit: initialLimit)
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
    cache = opened; plans = restored; plansURL = tasks
    return opened
  }
  func snapshot() throws -> Snapshot {
    let cache = try open()
    revision += 1
    return Snapshot(revision: revision, entries: cache.entries, plans: plans, bytes: cache.bytes, limit: cache.limit)
  }
  func page(_ url: URL, book: BookhouseFollowedBook) throws -> ForumPage? {
    try Task.checkCancellation()
    return try open().page(url, book: book)
  }
  func store(_ page: ForumPage, book: BookhouseFollowedBook, preservingBookID: String?) throws -> Snapshot {
    try Task.checkCancellation()
    try open().store(page, book: book, preservingBookID: preservingBookID)
    return try snapshot()
  }
  func searchDocuments(books: [BookhouseFollowedBook]) throws -> [BookhouseOfflineSearch.Document] {
    try Task.checkCancellation()
    return try open().searchDocuments(books: books)
  }
  func enqueue(_ book: BookhouseFollowedBook, chapters: [BookhouseChapter]) throws -> Snapshot {
    _ = try open()
    try updatePlans {
      if let index = $0.firstIndex(where: { $0.bookID == book.id }) { $0[index].include(chapters) }
      else { $0.append(BookhouseOfflinePlan(bookID: book.id, chapters: chapters)) }
    }
    return try snapshot()
  }
  func reconcile(_ bookID: String) throws -> Snapshot {
    let cache = try open()
    try updatePlans { values in
      guard let index = values.firstIndex(where: { $0.bookID == bookID }) else { return }
      values[index].reconcile { cache.contains($0, bookID: bookID) }
    }
    return try snapshot()
  }
  func advance(_ planID: UUID, target: URL) throws -> Snapshot {
    try Task.checkCancellation()
    _ = try open()
    try updatePlans { values in
      if let index = values.firstIndex(where: { $0.id == planID }) { values[index].advance(target) }
    }
    return try snapshot()
  }
  func remove(_ planID: UUID) throws -> Snapshot {
    _ = try open()
    try updatePlans { $0.removeAll { $0.id == planID } }
    return try snapshot()
  }
  func finish(_ planID: UUID) throws -> Snapshot {
    _ = try open()
    // An enqueue may extend a completed plan while the worker is awaiting this actor.
    try updatePlans { $0.removeAll { $0.id == planID && $0.next == nil } }
    return try snapshot()
  }
  func setLimit(_ bytes: Int, preservingBookID: String?) throws -> Snapshot {
    try open().setLimit(bytes, preservingBookID: preservingBookID)
    return try snapshot()
  }
  func clear() throws -> Snapshot {
    try open().clear()
    return try snapshot()
  }
  private func updatePlans(_ change: (inout [BookhouseOfflinePlan]) -> Void) throws {
    guard var url = plansURL else { throw ReaderFailure.storage }
    var updated = plans; change(&updated)
    try JSONEncoder().encode(updated).write(to: url, options: .atomic)
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try? url.setResourceValues(values)
    plans = updated
  }
}
