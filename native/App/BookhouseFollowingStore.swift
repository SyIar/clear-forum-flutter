import Foundation
import ForumUI

extension LibraryStore {
  @discardableResult func followBook(_ entry: ForumEntry, session: ForumSession) -> String? {
    guard site == .bookhouse, session.site == .bookhouse else { return nil }
    if let existing = document.followedBook(for: entry) { return existing.id }
    guard document.followedBooks.count < 100, let book = BookhouseFollowedBook(entry: entry) else {
      error = AppText.text("A book needs a numbered chapter title and an author to follow.")
      return nil
    }
    change { $0.followedBooks[book.id] = book }
    guard document.followedBooks[book.id] != nil else { return nil }
    Task { await refreshBook(book.id, session: session) }
    return book.id
  }
  func unfollowBook(_ id: String) {
    bookTasks[id]?.cancel()
    change { $0.followedBooks.removeValue(forKey: id) }
    bookRefreshPhases.removeValue(forKey: id); bookErrors.removeValue(forKey: id)
  }
  func recordBook(_ id: String, url: URL, chapter: Int, paragraph: Int) {
    guard let book = document.followedBooks[id],
          book.position != BookhouseReadingPosition(url: url, chapter: chapter, paragraph: paragraph) else { return }
    change { $0.followedBooks[id]?.record(url: url, chapter: chapter, paragraph: paragraph) }
  }
  func refreshBooks(session: ForumSession, manual: Bool = false) async {
    guard site == .bookhouse, session.site == .bookhouse, !checkProgress.running else { return }
    let targets = document.readingBooks.filter { LibraryRefreshPolicy.isDue(checkedAt: $0.checkedAt, attemptedAt: $0.attemptedAt, manual: manual) }
    guard !targets.isEmpty else { if manual { checkProgress = LibraryCheckProgress(skippedFresh: true) }; return }
    checkProgress = LibraryCheckProgress(running: true, total: targets.count)
    defer { checkProgress.running = false; checkProgress.currentTitle = nil; checkProgress.finishedAt = Date() }
    for book in targets {
      guard !Task.isCancelled else { return }
      checkProgress.currentTitle = book.title
      await refreshBook(book.id, session: session, manual: manual)
      checkProgress.completed += 1
      if bookRefreshPhases[book.id] == .updated { checkProgress.updated += 1 }
      if bookRefreshPhases[book.id] == .failed { checkProgress.failed += 1 }
    }
  }
  func refreshBook(_ id: String, session: ForumSession, manual: Bool = true) async {
    guard site == .bookhouse, session.site == .bookhouse else { return }
    if let task = bookTasks[id] { await task.value; return }
    guard let book = document.followedBooks[id], let search = BookhouseSitePolicy.search(book.catalogKeywords),
          LibraryRefreshPolicy.isDue(checkedAt: book.checkedAt, attemptedAt: book.attemptedAt, manual: manual) else { return }
    change { $0.followedBooks[id]?.attemptedAt = Date() }
    bookRefreshPhases[id] = .checking; bookErrors[id] = nil
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        self.bookTasks[id] = nil
        if self.bookRefreshPhases[id] == .checking { self.bookRefreshPhases[id] = nil }
      }
      do {
        var indexedBook = book
        // Declared literary authors can be indexed even if the original upload disappears.
        if indexedBook.authorSource != .title {
          let seed = try await session.load(book.seed)
          guard indexedBook.verifySeed(seed) else { throw BookhouseFollowingFailure.author }
        }
        var next: URL? = search
        var visited = Set<String>(), entries: [ForumEntry] = []
        while let url = next {
          try Task.checkCancellation()
          guard visited.count < 50, BookhouseSitePolicy.pageRoot(url) == BookhouseSitePolicy.pageRoot(search),
                visited.insert(BookhouseSitePolicy.pageCacheKey(url)).inserted else { throw BookhouseFollowingFailure.catalog }
          let page = try await session.load(url)
          guard page.kind == .threads, BookhouseSitePolicy.pageRoot(page.url) == BookhouseSitePolicy.pageRoot(search) else {
            throw BookhouseFollowingFailure.catalog
          }
          entries += page.entries.filter(indexedBook.matchesCatalogResult)
          guard entries.count <= 5_000 else { throw BookhouseFollowingFailure.catalog }
          next = page.next
        }
        try Task.checkCancellation()
        guard self.document.followedBooks[id]?.followedAt == book.followedAt else { return }
        guard !entries.isEmpty else { throw BookhouseFollowingFailure.catalog }
        let date = Date()
        self.change {
          // Merge into the latest record so an in-flight check cannot erase reading progress.
          $0.followedBooks[id]?.mergeCatalog(entries, verifiedBy: indexedBook, checkedAt: date)
        }
        guard self.document.followedBooks[id]?.checkedAt == date else { throw ReaderFailure.storage }
        self.bookRefreshPhases[id] = (self.document.followedBooks[id]?.latestChapter ?? 0) > book.latestChapter && book.checkedAt != nil ? .updated : .checked
      } catch {
        guard !Task.isCancelled, self.document.followedBooks[id]?.followedAt == book.followedAt else { return }
        self.bookRefreshPhases[id] = .failed
        self.bookErrors[id] = AppText.error(error)
      }
    }
    bookTasks[id] = task
    await task.value
  }
}

enum BookhouseFollowingFailure: Error, LocalizedError {
  case author, catalog
  var errorDescription: String? {
    switch self {
    case .author: return AppText.text("This post does not match the followed book and author.")
    case .catalog: return AppText.text("Could not check every catalog page. Your existing chapters and position are kept.")
    }
  }
}
