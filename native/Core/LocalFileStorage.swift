import Foundation

public struct LocalStorageSnapshot: Sendable {
  public let files: [LocalFileEntry]
  public let bytes: Int64
  public let skipped: Int
}

extension LocalFileCatalog {
  /// Recursively measures local Documents files without opening their contents.
  public func storage(in path: [String] = []) throws -> LocalStorageSnapshot {
    let folder = try url(for: path)
    guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw Failure.unavailable }
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
    var skipped = 0
    guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [],
      errorHandler: { _, _ in skipped += 1; return true }) else { throw Failure.unavailable }
    var files: [LocalFileEntry] = []
    var bytes: Int64 = 0
    while let file = enumerator.nextObject() as? URL {
      try Task.checkCancellation()
      guard let values = try? file.resourceValues(forKeys: keys) else { skipped += 1; enumerator.skipDescendants(); continue }
      if values.isSymbolicLink == true { skipped += 1; enumerator.skipDescendants(); continue }
      guard values.isRegularFile == true else { continue }
      guard let size = values.fileSize, size >= 0, Int64(size) <= Int64.max - bytes else { skipped += 1; continue }
      let relative = Array(file.standardizedFileURL.pathComponents.dropFirst(root.pathComponents.count))
      // Keep deletion routes anchored to this catalog rather than a display name.
      guard !relative.isEmpty, file.standardizedFileURL.path.hasPrefix(root.path + "/") else { throw Failure.unavailable }
      files.append(LocalFileEntry(path: relative, directory: false, bytes: Int64(size), modified: values.contentModificationDate))
      bytes += Int64(size)
    }
    files.sort {
      if $0.bytes != $1.bytes { return ($0.bytes ?? 0) > ($1.bytes ?? 0) }
      return $0.path.joined(separator: "/").localizedStandardCompare($1.path.joined(separator: "/")) == .orderedAscending
    }
    return LocalStorageSnapshot(files: files, bytes: bytes, skipped: skipped)
  }

  /// Requires a selected entry and revalidates its identity after confirmation.
  /// The Documents root and paths crossing symbolic links cannot be removed.
  public func remove(_ entry: LocalFileEntry) throws {
    guard !entry.path.isEmpty else { throw Failure.unavailable }
    let target = try url(for: entry.path)
    guard target != root, target.path.hasPrefix(root.path + "/") else { throw Failure.unavailable }
    let values = try target.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
    guard values.isDirectory == entry.directory,
          entry.modified == nil || values.contentModificationDate == entry.modified,
          entry.directory || entry.bytes == nil || values.fileSize.map(Int64.init) == entry.bytes else { throw Failure.unavailable }
    try FileManager.default.removeItem(at: target)
  }
}
