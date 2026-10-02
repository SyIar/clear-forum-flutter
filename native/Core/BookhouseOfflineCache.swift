import Foundation

final class BookhouseOfflineCache {
  struct Entry: Codable {
    let id: UUID
    let bookID: String
    let url: URL
    let bytes: Int
    var accessed: Date
  }
  private let directory: URL
  private(set) var entries: [Entry]
  private(set) var limit: Int
  var bytes: Int { entries.reduce(0) { $0 + $1.bytes } }
  init(directory: URL, limit: Int = 100 * 1024 * 1024) throws {
    self.directory = directory; self.limit = max(1, limit)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let index = directory.appendingPathComponent("index.json")
    entries = FileManager.default.fileExists(atPath: index.path)
      ? try JSONDecoder().decode([Entry].self, from: Data(contentsOf: index)) : []
    entries = entries.filter { $0.bytes > 0 && BookhouseSitePolicy.threadKey($0.url) != nil && FileManager.default.fileExists(atPath: file($0.id).path) }
    try trim()
    let retained = Set(entries.map { $0.id.uuidString + ".json" })
    for candidate in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where candidate.pathExtension == "json" && UUID(uuidString: candidate.deletingPathExtension().lastPathComponent) != nil && !retained.contains(candidate.lastPathComponent) {
      try? FileManager.default.removeItem(at: candidate)
    }
  }
  func contains(_ url: URL, bookID: String) -> Bool { entry(url, bookID: bookID) != nil }
  func page(_ url: URL, book: BookhouseFollowedBook) throws -> ForumPage? {
    guard let index = entry(url, bookID: book.id) else { return nil }
    let value = try JSONDecoder().decode(ForumPage.self, from: Data(contentsOf: file(entries[index].id)))
    guard book.accepts(value), BookhouseSitePolicy.threadKey(value.url) == BookhouseSitePolicy.threadKey(url) else { return nil }
    entries[index].accessed = Date(); try save()
    return value
  }
  func store(_ page: ForumPage, book: BookhouseFollowedBook) throws {
    guard page.kind == .posts, book.accepts(page) else { throw ReaderFailure.unsupported }
    let data = try JSONEncoder().encode(page)
    guard data.count <= limit else { throw ReaderFailure.storage }
    let record = Entry(id: UUID(), bookID: book.id, url: page.url, bytes: data.count, accessed: Date())
    try data.write(to: file(record.id), options: .atomic)
    let old = entries
    entries.removeAll { $0.bookID == book.id && BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(page.url) }
    entries.append(record)
    do { try trim() } catch { entries = old; try? FileManager.default.removeItem(at: file(record.id)); throw error }
    for removed in old where !entries.contains(where: { $0.id == removed.id }) { try? FileManager.default.removeItem(at: file(removed.id)) }
  }
  func setLimit(_ bytes: Int) throws { limit = max(1, bytes); try trim() }
  func clear() throws {
    let old = entries; entries = []
    do { try save() } catch { entries = old; throw error }
    for entry in old { try? FileManager.default.removeItem(at: file(entry.id)) }
  }
  private func trim() throws {
    let old = entries
    entries.sort { $0.accessed < $1.accessed }
    while bytes > limit || entries.count > 2000 { entries.removeFirst() }
    do { try save() } catch { entries = old; throw error }
    for removed in old where !entries.contains(where: { $0.id == removed.id }) { try? FileManager.default.removeItem(at: file(removed.id)) }
  }
  private func entry(_ url: URL, bookID: String) -> Int? {
    entries.firstIndex { $0.bookID == bookID && BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(url) }
  }
  private func file(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
  private func save() throws { try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent("index.json"), options: .atomic) }
}

extension BookhouseFollowedBook {
  // Include the current publication and every split part covering the next five chapter numbers.
  var offlineTargets: [BookhouseChapter] {
    let first = position?.chapter ?? chapters.first?.first ?? 1
    let end = min(100_000, first + 5)
    return Array(chapters.filter { $0.last >= first && $0.first <= end }.prefix(50))
  }
}
