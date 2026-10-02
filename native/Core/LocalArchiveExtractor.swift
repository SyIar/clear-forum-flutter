import Foundation
import ArchiveSupport

/// Expands a local ZIP into a new sibling folder, publishing only a complete result.
enum LocalArchiveExtractor {
  enum Failure: Error { case invalidArchive, unsafePath, tooLarge, insufficientSpace, unavailableDestination, passwordRequired, incorrectPassword, unsupportedEncryption }
  struct Limits {
    var entries = 50_000
    var bytes: UInt64 = 128 * 1024 * 1024 * 1024
  }

  static func extract(_ path: [String], in catalog: LocalFileCatalog,
                      progress: Progress, password: String? = nil, limits: Limits = Limits()) throws -> [String] {
    func checkCancellation() throws {
      if progress.isCancelled { throw CancellationError() }
      try Task.checkCancellation()
    }
    try checkCancellation()
    guard limits.entries >= 0, limits.bytes <= UInt64(Int64.max / 2) else { throw Failure.tooLarge }
    let source = try catalog.url(for: path)
    guard source.pathExtension.lowercased() == "zip",
          try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw Failure.invalidArchive }
    let parentPath = Array(path.dropLast())
    let parent = try catalog.url(for: parentPath)
    let expectedCount = try entryCount(in: source)
    guard expectedCount <= UInt64(limits.entries) else { throw Failure.tooLarge }
    let archive = try FLZipReader(path: source.path)
    var entries: [(FLZipEntry, [String])] = []
    var total: UInt64 = 0
    var pathBytes = 0
    while let entry = try archive.nextEntry() {
      try checkCancellation()
      guard !entry.unsafe else { throw Failure.unsafePath }
      let parts = try components(entry.path)
      pathBytes += entry.path.utf8.count
      guard entries.count < limits.entries, pathBytes <= 16 * 1024 * 1024,
            entry.size <= limits.bytes - total else { throw Failure.tooLarge }
      total += entry.size
      entries.append((entry, parts))
    }
    // Never publish an incompletely enumerated ZIP or a partially unlocked one.
    guard UInt64(entries.count) == expectedCount else { throw Failure.invalidArchive }
    if entries.contains(where: { $0.0.encrypted }), password == nil { throw Failure.passwordRequired }
    if let free = try FileManager.default.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber {
      guard free.uint64Value > total, free.uint64Value - total > 64 * 1024 * 1024 else { throw Failure.insufficientSpace }
    }
    progress.totalUnitCount = Int64(total) + Int64(entries.count) + 1
    progress.completedUnitCount = 0
    let manager = FileManager.default
    let staging = manager.temporaryDirectory.appendingPathComponent("ForumLite-Unzip-" + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: staging) }
    try archive.rewind()
    for (entry, parts) in entries {
      try checkCancellation()
      guard let current = try archive.nextEntry(), current.path == entry.path, current.size == entry.size,
            current.encrypted == entry.encrypted, current.directory == entry.directory, !current.unsafe else { throw Failure.invalidArchive }
      var target = staging
      for part in parts { target.appendPathComponent(part) }
      guard target.standardizedFileURL.path.hasPrefix(staging.standardizedFileURL.path + "/") else { throw Failure.unsafePath }
      if entry.directory {
        guard entry.size == 0 else { throw Failure.invalidArchive }
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
      } else {
        try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !manager.fileExists(atPath: target.path), manager.createFile(atPath: target.path, contents: nil) else { throw Failure.invalidArchive }
        let output = try FileHandle(forWritingTo: target)
        defer { try? output.close() }
        try consume(archive, encrypted: entry.encrypted, password: password, progress: progress) { data in
          try output.write(contentsOf: data)
        }
        if let date = entry.modified {
          try manager.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
        }
      }
      // Empty encrypted directory entries also have password/authentication data.
      if entry.directory { try consume(archive, encrypted: entry.encrypted, password: password, progress: progress) { _ in } }
      progress.completedUnitCount += 1
    }
    try checkCancellation()
    guard try catalog.url(for: parentPath) == parent else { throw Failure.unsafePath }
    let name = source.deletingPathExtension().lastPathComponent
    let stem = name.isEmpty || name == "." || name == ".." ? "Archive" : String(name.prefix(100))
    for suffix in 1...10_000 {
      let folderName = suffix == 1 ? stem : "\(stem) (\(suffix))"
      let destination = parent.appendingPathComponent(folderName, isDirectory: true)
      do {
        // moveItem refuses existing paths, including a colliding empty folder.
        try manager.moveItem(at: staging, to: destination)
        progress.completedUnitCount = progress.totalUnitCount
        return parentPath + [folderName]
      } catch let error as CocoaError where error.code == .fileWriteFileExists { continue }
    }
    throw Failure.unavailableDestination
  }

  private static func consume(_ archive: FLZipReader, encrypted: Bool, password: String?, progress: Progress,
                              write: (Data) throws -> Void) throws {
    do {
      try archive.openEntry(password: password)
      while true {
        if progress.isCancelled { throw CancellationError() }
        try Task.checkCancellation()
        let data = try autoreleasepool { try archive.readChunk() }
        if data.isEmpty { break }
        try write(data)
        progress.completedUnitCount += Int64(data.count)
      }
      try archive.finishEntry()
    } catch let error as NSError where error.domain == FLZipErrorDomain {
      if error.code == -109 { throw Failure.unsupportedEncryption }
      if encrypted && [-108, -106, -105, -3].contains(error.code) { throw Failure.incorrectPassword }
      throw Failure.invalidArchive
    }
  }

  private static func components(_ path: String) throws -> [String] {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    let clean = path.hasSuffix("/") ? Array(parts.dropLast()) : parts
    guard !clean.isEmpty, clean.count <= 64, path.utf8.count <= 4096,
          clean.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && !$0.contains("\0") }) else {
      throw Failure.unsafePath
    }
    return clean
  }

  // Read only the bounded ZIP footer to detect truncated enumeration, including
  // ZIP64 archives. File contents are streamed by minizip, never buffered whole.
  private static func entryCount(in file: URL) throws -> UInt64 {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    guard size >= 22 else { throw Failure.invalidArchive }
    func read(at offset: UInt64, count: Int) throws -> Data {
      guard offset <= size, UInt64(count) <= size - offset else { throw Failure.invalidArchive }
      try handle.seek(toOffset: offset)
      let data = try handle.read(upToCount: count) ?? Data()
      guard data.count == count else { throw Failure.invalidArchive }
      return data
    }
    func value(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
      data[offset..<(offset + count)].enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
    }
    let tailSize = Int(min(size, 65_557))
    let tail = try read(at: size - UInt64(tailSize), count: tailSize)
    for offset in stride(from: tail.count - 22, through: 0, by: -1) {
      guard value(tail, offset, 4) == 0x06054b50,
            offset + 22 + Int(value(tail, offset + 20, 2)) == tail.count else { continue }
      guard value(tail, offset + 4, 2) == 0, value(tail, offset + 6, 2) == 0,
            value(tail, offset + 8, 2) == value(tail, offset + 10, 2) else { throw Failure.invalidArchive }
      let count = value(tail, offset + 10, 2)
      let endOffset = size - UInt64(tailSize) + UInt64(offset)
      if endOffset >= 20 {
        let locator = try read(at: endOffset - 20, count: 20)
        if value(locator, 0, 4) == 0x07064b50 {
          guard value(locator, 4, 4) == 0, value(locator, 16, 4) == 1 else { throw Failure.invalidArchive }
          let zip64 = try read(at: value(locator, 8, 8), count: 56)
          guard value(zip64, 0, 4) == 0x06064b50, value(zip64, 4, 8) >= 44,
                value(zip64, 16, 4) == 0, value(zip64, 20, 4) == 0,
                value(zip64, 24, 8) == value(zip64, 32, 8) else { throw Failure.invalidArchive }
          return value(zip64, 32, 8)
        }
      }
      guard count < 65_535 else { throw Failure.invalidArchive }
      return count
    }
    throw Failure.invalidArchive
  }
}
