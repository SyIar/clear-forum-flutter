import Foundation
import Combine

@MainActor
final class BookhouseOfflineStore: ObservableObject {
  static let shared = BookhouseOfflineStore()
  @Published private(set) var activeBook: String?
  @Published private(set) var plans: [BookhouseOfflinePlan] = []
  @Published private(set) var failedBooks = Set<String>()
  @Published private(set) var bytes = 0
  @Published private(set) var limitMB: Int
  @Published private(set) var error: String?
  private var cache: BookhouseOfflineCache?
  private var worker: Task<Void, Never>?
  private var plansURL: URL?
  private var books: [String: BookhouseFollowedBook] = [:]
  private var ready = false
  private var paused = false
  var busy: Bool { activeBook != nil }
  var completed: Int { plans.first { $0.bookID == activeBook }?.completed ?? 0 }
  var total: Int { plans.first { $0.bookID == activeBook }?.targets.count ?? 0 }
  func plan(for bookID: String) -> BookhouseOfflinePlan? { plans.first { $0.bookID == bookID } }
  func caching(_ bookID: String) -> Bool { !paused && books[bookID] != nil && !failedBooks.contains(bookID) && plan(for: bookID) != nil }
  private init() {
    let limit = UserDefaults.standard.integer(forKey: "bookhouse.offlineLimit")
    limitMB = [50, 100, 250].contains(limit) ? limit : 100
    do {
      let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      var directory = support.appendingPathComponent("OfflineBooks", isDirectory: true)
      cache = try BookhouseOfflineCache(directory: directory, limit: limitMB * 1024 * 1024)
      var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
      bytes = cache?.bytes ?? 0
      let tasks = support.appendingPathComponent("OfflineBookTasks.json")
      plansURL = tasks
      if FileManager.default.fileExists(atPath: tasks.path) {
        let restored = try JSONDecoder().decode([BookhouseOfflinePlan].self, from: Data(contentsOf: tasks))
        guard restored.allSatisfy(\.valid), Set(restored.map(\.bookID)).count == restored.count else { throw ReaderFailure.storage }
        plans = restored
      }
      ready = true
    } catch { self.error = AppText.text("Could not open the offline chapter cache.") }
  }
  func contains(_ url: URL, bookID: String) -> Bool { cache?.contains(url, bookID: bookID) == true }
  func captureRead(_ page: ForumPage, book: BookhouseFollowedBook) {
    guard let cache else { return }
    do { try cache.store(page, book: book, preservingBookID: activeBook); bytes = cache.bytes }
    catch { self.error = AppText.text("Could not cache this chapter. Reading can continue.") }
  }
  func search(_ query: String, books: [BookhouseFollowedBook]) async throws -> BookhouseOfflineSearch.Result {
    guard let cache else { throw MediaFileError(message: AppText.text("Could not open the offline chapter cache.")) }
    let documents = cache.searchDocuments(books: books)
    let worker = Task.detached(priority: .userInitiated) { try BookhouseOfflineSearch.search(query, documents: documents) }
    return try await withTaskCancellationHandler {
      try await worker.value
    } onCancel: { worker.cancel() }
  }
  func page(_ url: URL, book: BookhouseFollowedBook) -> ForumPage? {
    do { return try cache?.page(url, book: book) }
    catch { self.error = AppText.text("Could not read this offline chapter. Refresh to load it again."); return nil }
  }
  func download(_ book: BookhouseFollowedBook, session: ForumSession) {
    enqueue(book, chapters: book.offlineTargets, session: session)
  }
  func downloadAll(_ book: BookhouseFollowedBook, session: ForumSession) {
    enqueue(book, chapters: book.chapters, session: session)
  }
  private func enqueue(_ book: BookhouseFollowedBook, chapters: [BookhouseChapter], session: ForumSession) {
    guard ready, session.site == .bookhouse, !chapters.isEmpty else { return }
    do {
      try updatePlans {
        if let index = $0.firstIndex(where: { $0.bookID == book.id }) { $0[index].include(chapters) }
        else { $0.append(BookhouseOfflinePlan(bookID: book.id, chapters: chapters)) }
      }
      error = nil; resume(book, session: session)
    } catch { self.error = AppText.error(error) }
  }
  // Resumption is tied to opening this book, not to presenting its chapter sheet.
  func resume(_ book: BookhouseFollowedBook, session: ForumSession) {
    guard ready, session.site == .bookhouse, let cache, plan(for: book.id) != nil else { return }
    books[book.id] = book; paused = false; failedBooks.remove(book.id)
    if activeBook != book.id {
      do {
        try updatePlans { values in
          guard let index = values.firstIndex(where: { $0.bookID == book.id }) else { return }
          values[index].reconcile { cache.contains($0, bookID: book.id) }
        }
      } catch { self.error = AppText.error(error); failedBooks.insert(book.id); return }
    }
    start(session: session)
  }
  private func start(session: ForumSession) {
    guard ready, !paused, worker == nil, let cache,
          plans.contains(where: { books[$0.bookID] != nil && !failedBooks.contains($0.bookID) }) else { return }
    worker = Task { [weak self] in
      guard let self else { return }
      defer {
        self.activeBook = nil; self.worker = nil; self.bytes = cache.bytes
        self.start(session: session)
      }
      while !Task.isCancelled, !self.paused,
            let plan = self.plans.first(where: { self.books[$0.bookID] != nil && !self.failedBooks.contains($0.bookID) }),
            let book = self.books[plan.bookID] {
        self.activeBook = book.id
        do {
          try Task.checkCancellation()
          guard let target = plan.next else {
            try self.updatePlans { $0.removeAll { $0.id == plan.id } }
            continue
          }
          guard book.chapters.contains(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(target) }) else { throw ReaderFailure.unsupported }
          var fetched = false
          if self.page(target, book: book) == nil {
            let page = try await session.load(target, cacheResult: true)
            try Task.checkCancellation()
            try cache.store(page, book: book, preservingBookID: book.id)
            fetched = true
          }
          try Task.checkCancellation()
          try self.updatePlans { values in
            if let index = values.firstIndex(where: { $0.id == plan.id }) { values[index].advance(target) }
          }
          self.bytes = cache.bytes
          if fetched { try await Task.sleep(for: .milliseconds(700)) }
          else { await Task.yield() }
        } catch is CancellationError { return }
        catch {
          if Task.isCancelled { return }
          self.failedBooks.insert(book.id)
          self.error = error is BookhouseOfflineFailure
            ? AppText.text("The offline cache is full. Increase its limit in reading settings, then resume caching.") : AppText.error(error)
        }
      }
    }
  }
  private func updatePlans(_ change: (inout [BookhouseOfflinePlan]) -> Void) throws {
    guard ready, var url = plansURL else { throw ReaderFailure.storage }
    var updated = plans; change(&updated)
    try JSONEncoder().encode(updated).write(to: url, options: .atomic)
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try? url.setResourceValues(values)
    plans = updated
  }
  func pause() { paused = true; worker?.cancel() }
  func cancel() {
    guard let activeBook else { return }
    do { try updatePlans { $0.removeAll { $0.bookID == activeBook } }; worker?.cancel() }
    catch { self.error = AppText.error(error) }
  }
  func setLimit(_ value: Int) {
    guard [50, 100, 250].contains(value) else { return }
    do { try cache?.setLimit(value * 1024 * 1024, preservingBookID: activeBook); limitMB = value; bytes = cache?.bytes ?? 0; UserDefaults.standard.set(value, forKey: "bookhouse.offlineLimit") }
    catch { self.error = error is BookhouseOfflineFailure ? AppText.text("The offline cache is full. Increase its limit in reading settings, then resume caching.") : AppText.error(error) }
  }
  func clear() {
    guard !busy else { return }
    do { try cache?.clear(); bytes = cache?.bytes ?? 0; error = nil }
    catch { self.error = AppText.error(error) }
  }
}
