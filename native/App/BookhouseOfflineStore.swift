import Foundation
import Combine

@MainActor
final class BookhouseOfflineStore: ObservableObject {
  static let shared = BookhouseOfflineStore()
  @Published private(set) var activeBook: String?
  @Published private(set) var completed = 0
  @Published private(set) var total = 0
  @Published private(set) var bytes = 0
  @Published private(set) var limitMB: Int
  @Published private(set) var error: String?
  private var cache: BookhouseOfflineCache?
  private var worker: Task<Void, Never>?
  var busy: Bool { activeBook != nil }
  private init() {
    let limit = UserDefaults.standard.integer(forKey: "bookhouse.offlineLimit")
    limitMB = [50, 100, 250].contains(limit) ? limit : 100
    do {
      let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      var directory = support.appendingPathComponent("OfflineBooks", isDirectory: true)
      cache = try BookhouseOfflineCache(directory: directory, limit: limitMB * 1024 * 1024)
      var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
      bytes = cache?.bytes ?? 0
    } catch { self.error = AppText.text("Could not open the offline chapter cache.") }
  }
  func contains(_ url: URL, bookID: String) -> Bool { cache?.contains(url, bookID: bookID) == true }
  func captureRead(_ page: ForumPage, book: BookhouseFollowedBook) {
    guard let cache else { return }
    do { try cache.store(page, book: book); bytes = cache.bytes }
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
    guard !busy, session.site == .bookhouse, let cache else { return }
    let targets = book.offlineTargets
    guard !targets.isEmpty else { return }
    activeBook = book.id; total = targets.count; completed = 0; error = nil
    worker = Task { [weak self] in
      guard let self else { return }
      defer { self.activeBook = nil; self.worker = nil; self.bytes = cache.bytes }
      for chapter in targets {
        do {
          try Task.checkCancellation()
          if self.page(chapter.url, book: book) == nil {
            let page = try await session.load(chapter.url, cacheResult: true)
            try Task.checkCancellation()
            try cache.store(page, book: book)
          }
          self.completed += 1; self.bytes = cache.bytes
          try await Task.sleep(for: .milliseconds(700))
        } catch is CancellationError { return }
        catch { self.error = AppText.error(error); return }
      }
    }
  }
  func cancel() { worker?.cancel() }
  func setLimit(_ value: Int) {
    guard [50, 100, 250].contains(value) else { return }
    do { try cache?.setLimit(value * 1024 * 1024); limitMB = value; bytes = cache?.bytes ?? 0; UserDefaults.standard.set(value, forKey: "bookhouse.offlineLimit") }
    catch { self.error = AppText.error(error) }
  }
  func clear() {
    guard !busy else { return }
    do { try cache?.clear(); bytes = cache?.bytes ?? 0; error = nil }
    catch { self.error = AppText.error(error) }
  }
}
