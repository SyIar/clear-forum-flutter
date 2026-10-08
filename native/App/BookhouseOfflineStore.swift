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
  @Published private var entries: [BookhouseOfflineCache.Entry] = []
  @Published private var maintaining = false
  private let repository: BookhouseOfflineRepository
  private var revision = 0
  private var worker: Task<Void, Never>?
  private var session: ForumSession?
  private var books: [String: BookhouseFollowedBook] = [:]
  private var ready = false
  private var paused = false
  private var lifecycle = 0
  var busy: Bool { activeBook != nil || maintaining }
  var completed: Int { plans.first { $0.bookID == activeBook }?.completed ?? 0 }
  var total: Int { plans.first { $0.bookID == activeBook }?.targets.count ?? 0 }
  func plan(for bookID: String) -> BookhouseOfflinePlan? { plans.first { $0.bookID == bookID } }
  func caching(_ bookID: String) -> Bool { !paused && books[bookID] != nil && !failedBooks.contains(bookID) && plan(for: bookID) != nil }
  private init() {
    let limit = UserDefaults.standard.integer(forKey: "bookhouse.offlineLimit")
    limitMB = [50, 100, 250].contains(limit) ? limit : 100
    repository = BookhouseOfflineRepository(limit: limitMB * 1024 * 1024)
    Task {
      do { try await prepare() }
      catch { self.error = AppText.text("Could not open the offline chapter cache.") }
    }
  }
  private func apply(_ snapshot: BookhouseOfflineRepository.Snapshot) {
    // Independent callers can resume in a different order than disk operations completed.
    guard snapshot.revision > revision else { return }
    revision = snapshot.revision; ready = true
    entries = snapshot.entries; plans = snapshot.plans; bytes = snapshot.bytes
    limitMB = snapshot.limit / (1024 * 1024)
  }
  private func prepare() async throws {
    if !ready { apply(try await repository.snapshot()) }
  }
  func contains(_ url: URL, bookID: String) -> Bool {
    entries.contains { $0.bookID == bookID && BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(url) }
  }
  func captureRead(_ page: ForumPage, book: BookhouseFollowedBook) {
    let preservingBookID = activeBook
    // This task belongs to the store, so leaving the reading view does not discard a save.
    Task {
      do { apply(try await repository.store(page, book: book, preservingBookID: preservingBookID)) }
      catch { self.error = AppText.text("Could not cache this chapter. Reading can continue.") }
    }
  }
  func search(_ query: String, books: [BookhouseFollowedBook]) async throws -> BookhouseOfflineSearch.Result {
    let documents = try await repository.searchDocuments(books: books)
    try Task.checkCancellation()
    let search = Task.detached(priority: .userInitiated) { try BookhouseOfflineSearch.search(query, documents: documents) }
    return try await withTaskCancellationHandler {
      try await search.value
    } onCancel: { search.cancel() }
  }
  func page(_ url: URL, book: BookhouseFollowedBook) async -> ForumPage? {
    do { return try await repository.page(url, book: book) }
    catch is CancellationError { return nil }
    catch { self.error = AppText.text("Could not read this offline chapter. Refresh to load it again."); return nil }
  }
  func download(_ book: BookhouseFollowedBook, session: ForumSession) {
    enqueue(book, chapters: book.offlineTargets, session: session)
  }
  func downloadAll(_ book: BookhouseFollowedBook, session: ForumSession) {
    enqueue(book, chapters: book.chapters, session: session)
  }
  private func enqueue(_ book: BookhouseFollowedBook, chapters: [BookhouseChapter], session: ForumSession) {
    guard session.site == .bookhouse, !chapters.isEmpty else { return }
    let generation = lifecycle
    Task {
      do {
        apply(try await repository.enqueue(book, chapters: chapters))
        error = nil
        try await activate(book, session: session, generation: generation)
      } catch { self.error = AppText.error(error) }
    }
  }
  // Resumption is tied to opening this book, not to presenting its chapter sheet.
  func resume(_ book: BookhouseFollowedBook, session: ForumSession) {
    guard session.site == .bookhouse else { return }
    let generation = lifecycle
    Task {
      do {
        try await prepare()
        try await activate(book, session: session, generation: generation)
      } catch { self.error = AppText.error(error); failedBooks.insert(book.id) }
    }
  }
  private func activate(_ book: BookhouseFollowedBook, session: ForumSession, generation: Int) async throws {
    guard generation == lifecycle, plan(for: book.id) != nil else { return }
    if activeBook != book.id { apply(try await repository.reconcile(book.id)) }
    guard generation == lifecycle, plan(for: book.id) != nil else { return }
    books[book.id] = book; self.session = session; paused = false; failedBooks.remove(book.id)
    start()
  }
  private func start() {
    guard ready, !paused, !maintaining, worker == nil, let session,
          plans.contains(where: { books[$0.bookID] != nil && !failedBooks.contains($0.bookID) }) else { return }
    worker = Task { [weak self] in
      guard let self else { return }
      defer {
        self.activeBook = nil; self.worker = nil
        self.start()
      }
      while !Task.isCancelled, !self.paused,
            let plan = self.plans.first(where: { self.books[$0.bookID] != nil && !self.failedBooks.contains($0.bookID) }),
            let book = self.books[plan.bookID] {
        self.activeBook = book.id
        do {
          try Task.checkCancellation()
          guard let target = plan.next else {
            self.apply(try await self.repository.finish(plan.id))
            continue
          }
          guard book.chapters.contains(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(target) }) else { throw ReaderFailure.unsupported }
          var fetched = false
          let cached = await self.page(target, book: book)
          try Task.checkCancellation()
          if cached == nil {
            let page = try await session.load(target, cacheResult: true)
            try Task.checkCancellation()
            self.apply(try await self.repository.store(page, book: book, preservingBookID: book.id))
            fetched = true
          }
          try Task.checkCancellation()
          self.apply(try await self.repository.advance(plan.id, target: target))
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
  func pause() { lifecycle += 1; paused = true; worker?.cancel() }
  func cancel() {
    guard let activeBook, let plan = plan(for: activeBook) else { return }
    books.removeValue(forKey: activeBook)
    worker?.cancel()
    Task {
      do { apply(try await repository.remove(plan.id)); start() }
      catch { self.error = AppText.error(error) }
    }
  }
  func setLimit(_ value: Int) {
    guard [50, 100, 250].contains(value) else { return }
    let preservingBookID = activeBook
    Task {
      do {
        apply(try await repository.setLimit(value * 1024 * 1024, preservingBookID: preservingBookID))
        UserDefaults.standard.set(limitMB, forKey: "bookhouse.offlineLimit")
      } catch { self.error = error is BookhouseOfflineFailure ? AppText.text("The offline cache is full. Increase its limit in reading settings, then resume caching.") : AppText.error(error) }
    }
  }
  func clear() {
    guard !busy, worker == nil else { return }
    maintaining = true
    Task {
      defer { maintaining = false; start() }
      do { apply(try await repository.clear()); error = nil }
      catch { self.error = AppText.error(error) }
    }
  }
}
