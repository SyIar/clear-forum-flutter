import Foundation

public struct LocalFileEntry: Identifiable, Hashable, Sendable {
  public let path: [String]
  public let directory: Bool
  public let bytes: Int64?
  public let modified: Date?
  public var compactedPath: [String]? = nil
  public var id: [String] { path }
  public var name: String { path.last ?? "" }
  public var displayName: String { compactedPath?.dropFirst(max(0, path.count - 1)).joined(separator: " / ") ?? name }
  public var destinationPath: [String] { compactedPath ?? path }
}

/// Lists only user files in one directory at a time, without reading file contents.
public struct LocalFileCatalog: Sendable {
  public enum Failure: Error { case unavailable }
  public let root: URL

  public init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }

  public func url(for path: [String]) throws -> URL {
    guard root.isFileURL, path.allSatisfy({
      !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") && !$0.contains("\0")
    }) else { throw Failure.unavailable }
    var target = root
    for part in path {
      target.appendPathComponent(part)
      // Do not follow links that Files or another importer may have placed here.
      let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey])
      guard values.isSymbolicLink != true else { throw Failure.unavailable }
    }
    let resolved = target.standardizedFileURL.resolvingSymlinksInPath()
    guard resolved == root || resolved.path.hasPrefix(root.path + "/") else { throw Failure.unavailable }
    let values = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
    guard values.isDirectory == true || values.isRegularFile == true else { throw Failure.unavailable }
    return resolved
  }

  public func entries(in path: [String] = []) throws -> [LocalFileEntry] {
    let directory = try url(for: path)
    guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw Failure.unavailable }
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
    let children = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
    var entries: [LocalFileEntry] = []
    for child in children {
      try Task.checkCancellation()
      // A file can be moved in Files while this list is being read.
      guard let values = try? child.resourceValues(forKeys: keys), values.isSymbolicLink != true,
            values.isDirectory == true || values.isRegularFile == true else { continue }
      let isDirectory = values.isDirectory == true
      entries.append(LocalFileEntry(path: path + [child.lastPathComponent], directory: isDirectory,
        bytes: isDirectory ? nil : values.fileSize.map(Int64.init), modified: values.contentModificationDate))
    }
    return entries.sorted {
      if $0.directory != $1.directory { return $0.directory }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  /// Compact directory-only chains for browsing without changing deletion scope.
  public func browserEntries(in path: [String] = []) throws -> [LocalFileEntry] {
    try entries(in: path).map { original in
      guard original.directory else { return original }
      var entry = original
      var destination = original.path
      for _ in 0..<64 {
        try Task.checkCancellation()
        guard let current = try? url(for: destination),
              let children = try? FileManager.default.contentsOfDirectory(at: current,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []),
              children.count == 1, let child = children.first,
              let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              !child.lastPathComponent.hasPrefix(".") else { break }
        let next = destination + [child.lastPathComponent]
        guard (try? url(for: next)) != nil else { break }
        destination = next
      }
      if destination != original.path { entry.compactedPath = destination }
      return entry
    }
  }
}
