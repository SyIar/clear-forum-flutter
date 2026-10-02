import Foundation

// Queue metadata and opaque resume tokens stay outside the Files-visible directory.
enum FileDownloadStore {
  static func root() throws -> URL {
    let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var directory = support.appendingPathComponent("FileDownloadState", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
    return directory
  }
  static func load<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
    let file = try root().appendingPathComponent(name + ".json")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    return try JSONDecoder().decode(type, from: Data(contentsOf: file))
  }
  static func save<T: Encodable>(_ value: T, name: String) throws {
    try JSONEncoder().encode(value).write(to: root().appendingPathComponent(name + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  static func remove(_ name: String) { if let root = try? root() { try? FileManager.default.removeItem(at: root.appendingPathComponent(name + ".json")) } }
  static func folder(_ name: String, parent: String) throws -> URL {
    guard DownloadQueuePolicy.safePath([name]) else { throw ReaderFailure.storage }
    let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    return documents.appendingPathComponent(parent, isDirectory: true).appendingPathComponent(name, isDirectory: true)
  }
  static func destination(_ path: [String], in directory: URL) throws -> URL {
    guard DownloadQueuePolicy.safePath(path) else { throw ReaderFailure.storage }
    let target = path.reduce(directory) { $0.appendingPathComponent($1) }.standardizedFileURL
    guard target.path.hasPrefix(directory.standardizedFileURL.path + "/") else { throw ReaderFailure.storage }
    return target
  }
  struct Receipt: Codable { let path: [String]; let bytes: Int64 }
  static func recovered(_ id: UUID, path: [String], directory: URL) throws -> URL? {
    guard let receipt = try load(Receipt.self, name: id.uuidString + "-receipt"), receipt.path == path else { return nil }
    let target = try destination(path, in: directory)
    guard FileManager.default.fileExists(atPath: target.path),
          (try target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) == receipt.bytes else { return nil }
    return target
  }
  static func install(_ file: URL, id: UUID, path: [String], directory: URL) throws -> URL {
    let target = try destination(path, in: directory)
    let bytes = Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    guard bytes > 0 else { throw ReaderFailure.storage }
    // Write the receipt first so a process exit between move and queue save is recoverable.
    try save(Receipt(path: path, bytes: bytes), name: id.uuidString + "-receipt")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: file, to: target)
    return target
  }
  static func acknowledge(_ id: UUID) { remove(id.uuidString); remove(id.uuidString + "-receipt") }
}

struct FileTransferCheckpoint: Codable {
  let url: URL
  let hosted: HostedFileRequest?
  let cookies: [VideoDownloadCookie]
  let userAgent: String
  var data: Data?
}

struct HostedBatchRecord: Codable {
  let id: UUID
  let created: Date
  let listing: HostedFileListing
  let phase: HostedBatchDownload.Phase
  let current: String
  let issue: String?
  let retryAfter: Date?
  let folder: String?
  let saved: [HostedBatchDownload.Saved]
  let skipped: [HostedBatchDownload.Skipped]
  let plan: HostedBatchPlan?
  let progress: Double?
}

struct GofileBatchRecord: Codable {
  let id: UUID
  let created: Date
  let sourceKey: String
  let title: String
  let url: URL
  let phase: GofileBatchDownload.Phase
  let current: String
  let issue: String?
  let gate: GofileFailure?
  let folder: String?
  let saved: [String: [String]]
  let skipped: [GofileBatchDownload.Skipped]
  let plan: GofileBatchPlan?
  let progress: Double?
}
