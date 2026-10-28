import Foundation
import CryptoKit

struct SouthOfflineThread: Codable, Identifiable {
  enum State: String, Codable { case pending, complete, partial, failed }
  let id: String
  let token: UUID
  let url: URL
  var title: String
  var savedAt: Date
  var totalPages = 1
  var savedPages: [Int] = []
  var imageCount = 0
  var missingImages = 0
  var bytes: Int64 = 0
  var state = State.pending
  var failure: String?
  var valid: Bool {
    SouthSitePolicy.threadKey(url) == id && SouthSitePolicy.threadRoot(url) == url &&
      (1...99_999).contains(totalPages) && savedPages.allSatisfy { (1...totalPages).contains($0) } &&
      Set(savedPages).count == savedPages.count && bytes >= 0 && imageCount >= 0 && missingImages >= 0 &&
      (state != .complete || savedPages.count == totalPages && missingImages == 0)
  }
}

// One actor owns the index, pages and image files. A per-download token prevents
// an old network callback from resurrecting a deleted or replaced thread.
actor SouthOfflineRepository {
  struct Snapshot { let revision: Int; let entries: [SouthOfflineThread] }
  private let suppliedDirectory: URL?
  private var directory: URL?
  private var entries: [SouthOfflineThread] = []
  private var revision = 0
  init(directory: URL? = nil) { suppliedDirectory = directory }

  private func open() throws -> URL {
    if let directory { return directory }
    var root = try suppliedDirectory ?? FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("OfflineSouth", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = root.appendingPathComponent("index.json")
    let restored = FileManager.default.fileExists(atPath: index.path)
      ? try JSONDecoder().decode([SouthOfflineThread].self, from: Data(contentsOf: index)) : []
    guard restored.allSatisfy(\.valid), Set(restored.map(\.id)).count == restored.count,
          Set(restored.map(\.token)).count == restored.count else { throw ReaderFailure.storage }
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try root.setResourceValues(values)
    entries = restored; directory = root
    return root
  }
  func snapshot() throws -> Snapshot {
    _ = try open(); revision += 1
    return Snapshot(revision: revision, entries: entries.sorted {
      $0.savedAt == $1.savedAt ? $0.id < $1.id : $0.savedAt > $1.savedAt
    })
  }
  private func save(_ updated: [SouthOfflineThread]) throws -> Snapshot {
    let root = try open()
    try JSONEncoder().encode(updated).write(to: root.appendingPathComponent("index.json"), options: .atomic)
    entries = updated
    return try snapshot()
  }
  private func index(_ token: UUID) throws -> Int {
    _ = try open()
    guard let index = entries.firstIndex(where: { $0.token == token }) else { throw CancellationError() }
    return index
  }
  private func folder(_ token: UUID) throws -> URL { try open().appendingPathComponent(token.uuidString, isDirectory: true) }
  private func imagePath(_ token: UUID, _ url: URL) throws -> URL {
    let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    return try folder(token).appendingPathComponent(name + ".image")
  }
  func enqueue(url: URL, title: String) throws -> Snapshot {
    _ = try open(); try Task.checkCancellation()
    guard let root = SouthSitePolicy.threadRoot(url), let id = SouthSitePolicy.threadKey(root) else { throw ReaderFailure.unsupported }
    var updated = entries
    if let index = updated.firstIndex(where: { $0.id == id }) {
      guard updated[index].state != .complete else { return try snapshot() }
      updated[index].state = .pending; updated[index].failure = nil
    } else {
      let entry = SouthOfflineThread(id: id, token: UUID(), url: root, title: title, savedAt: Date())
      try FileManager.default.createDirectory(at: folder(entry.token), withIntermediateDirectories: true)
      updated.append(entry)
    }
    return try save(updated)
  }
  func store(_ page: ForumPage, token: UUID, expectedPage: Int) throws -> Snapshot {
    try Task.checkCancellation()
    let index = try index(token), entry = entries[index]
    guard page.kind == .posts, !page.posts.isEmpty, SouthSitePolicy.threadKey(page.url) == entry.id,
          SouthSitePolicy.authorID(page.url) == nil, page.pageNumber == expectedPage,
          SouthSitePolicy.pageNumber(page.url) == expectedPage,
          (expectedPage == 1 || (1...entry.totalPages).contains(expectedPage)) else { throw ReaderFailure.unsupported }
    let file = try folder(token).appendingPathComponent("page-\(expectedPage).json")
    let data = try JSONEncoder().encode(page)
    guard data.count <= 16 * 1024 * 1024 else { throw ReaderFailure.storage }
    let oldSize = entry.savedPages.contains(expectedPage) ? (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 : 0
    try data.write(to: file, options: .atomic)
    var updated = entries
    if expectedPage == 1 {
      updated[index].totalPages = max(page.pageCount, updated[index].totalPages)
      updated[index].title = page.title
    }
    if !updated[index].savedPages.contains(expectedPage) { updated[index].savedPages.append(expectedPage) }
    updated[index].bytes += Int64(data.count - oldSize)
    return try save(updated)
  }
  func page(_ url: URL, threadID: String, normalizeNavigation: Bool = true) throws -> ForumPage? {
    _ = try open(); try Task.checkCancellation()
    guard let entry = entries.first(where: { $0.id == threadID }), SouthSitePolicy.threadKey(url) == entry.id,
          SouthSitePolicy.authorID(url) == nil else { return nil }
    let number = SouthSitePolicy.pageNumber(url)
    guard entry.savedPages.contains(number) else { return nil }
    let file = try folder(entry.token).appendingPathComponent("page-\(number).json")
    var page = try JSONDecoder().decode(ForumPage.self, from: Data(contentsOf: file))
    guard page.kind == .posts, page.pageNumber == number, SouthSitePolicy.threadKey(page.url) == entry.id,
          SouthSitePolicy.authorID(page.url) == nil else { throw ReaderFailure.storage }
    if normalizeNavigation {
      // Keep pagination inside the downloaded snapshot, even if the live thread grows.
      page.url = SouthSitePolicy.pageURL(entry.url, number: number)!
      page.previous = number > 1 ? SouthSitePolicy.pageURL(entry.url, number: number - 1) : nil
      page.next = number < entry.totalPages ? SouthSitePolicy.pageURL(entry.url, number: number + 1) : nil
      page.totalPages = entry.totalPages
      page.lastPage = SouthSitePolicy.pageURL(entry.url, number: entry.totalPages)
    }
    return page
  }
  func imageFile(_ url: URL, threadID: String) throws -> URL? {
    _ = try open(); try Task.checkCancellation()
    guard let entry = entries.first(where: { $0.id == threadID }) else { return nil }
    let file = try imagePath(entry.token, url)
    return FileManager.default.fileExists(atPath: file.path) ? file : nil
  }
  func storeImage(_ source: URL, url: URL, token: UUID) throws -> Snapshot {
    try Task.checkCancellation()
    let index = try index(token), target = try imagePath(token, url)
    guard source.isFileURL else { throw ReaderFailure.storage }
    if FileManager.default.fileExists(atPath: target.path) { return try snapshot() }
    let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard bytes > 0, bytes <= 100 * 1024 * 1024 else { throw ReaderFailure.storage }
    let staging = try folder(token).appendingPathComponent(UUID().uuidString + ".partial")
    defer { try? FileManager.default.removeItem(at: staging) }
    try FileManager.default.copyItem(at: source, to: staging)
    try FileManager.default.moveItem(at: staging, to: target)
    var updated = entries
    updated[index].bytes += Int64(bytes); updated[index].imageCount += 1
    do { return try save(updated) }
    catch { try? FileManager.default.removeItem(at: target); throw error }
  }
  func finish(_ token: UUID, missingImages: Int, failure: String? = nil) throws -> Snapshot {
    try Task.checkCancellation()
    let index = try index(token)
    var updated = entries
    updated[index].missingImages = missingImages
    updated[index].failure = failure
    // Recount committed files after a crash between an asset rename and index write.
    let files = try FileManager.default.contentsOfDirectory(at: folder(token), includingPropertiesForKeys: [.fileSizeKey])
    let committed = files.filter { $0.pathExtension == "json" || $0.pathExtension == "image" }
    updated[index].bytes = try committed.reduce(Int64(0)) { try $0 + Int64($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
    updated[index].imageCount = committed.filter { $0.pathExtension == "image" }.count
    if let failure { updated[index].state = .failed; updated[index].failure = failure }
    else {
      guard updated[index].savedPages.count == updated[index].totalPages else { throw ReaderFailure.storage }
      updated[index].state = missingImages == 0 ? .complete : .partial
      updated[index].savedAt = Date()
    }
    return try save(updated)
  }
  func remove(_ token: UUID) throws -> Snapshot {
    let index = try index(token), folder = try folder(token)
    var updated = entries; updated.remove(at: index)
    let result = try save(updated)
    // Once removed from the index, late writes fail their token check.
    try? FileManager.default.removeItem(at: folder)
    return result
  }
  func copyImageForViewer(_ url: URL, threadID: String) throws -> URL? {
    guard let source = try imageFile(url, threadID: threadID) else { return nil }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".image")
    try FileManager.default.copyItem(at: source, to: copy)
    return copy
  }
}

enum SouthOfflineImages {
  static func urls(in page: ForumPage) -> [URL] {
    var images: [URL] = []
    func append(_ url: URL?) { if let url { images.append(url) } }
    func walk(_ blocks: [BodyBlock]) {
      for block in blocks {
        if block.kind == .image { append(block.url); append(block.original) }
        append(block.poster)
        for run in block.runs { append(run.emoticon) }
        walk(block.children)
      }
    }
    for post in page.posts { append(post.avatar); append(post.avatarOriginal); walk(post.blocks) }
    var seen = Set<URL>()
    return images.filter { ["http", "https"].contains($0.scheme ?? "") && $0.host != nil && $0.user == nil && $0.password == nil && seen.insert($0).inserted }
  }
}
