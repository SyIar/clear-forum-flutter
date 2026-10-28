import Foundation

struct VideoDownloadContext: Codable {
  var url: URL
  var cookies: [VideoDownloadCookie]
  var turboID: String?
  var referer: URL
  var direct: Bool
}

struct VideoDownloadCookie: Codable {
  let name: String
  let value: String
  let domain: String
  let path: String
  let secure: Bool
  let expires: Date?
  init(_ cookie: HTTPCookie) {
    name = cookie.name; value = cookie.value; domain = cookie.domain; path = cookie.path
    secure = cookie.isSecure; expires = cookie.expiresDate
  }
  var cookie: HTTPCookie? {
    var values: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path, .secure: secure ? "TRUE" : "FALSE"]
    if let expires { values[.expires] = expires }
    return HTTPCookie(properties: values)
  }
}

struct VideoDownloadRecord: Codable {
  let id: UUID
  let source: URL
  let created: Date
  let phase: VideoDownload.Phase
  let context: VideoDownloadContext?
  let received: Int64
  let expected: Int64
  let localFilename: String?
  var origin: VideoOrigin?
}

// Account headers and opaque resume data stay outside the Files-visible Documents directory.
enum VideoDownloadStore {
  private static func directory() throws -> URL {
    let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var root = base.appendingPathComponent("VideoDownloads", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try root.setResourceValues(values)
    return root
  }
  static func load() throws -> [VideoDownloadRecord] {
    let file = try directory().appendingPathComponent("queue.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    return try JSONDecoder().decode([VideoDownloadRecord].self, from: Data(contentsOf: file))
  }
  static func save(_ records: [VideoDownloadRecord]) throws {
    try JSONEncoder().encode(records).write(to: directory().appendingPathComponent("queue.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
  static func resumeData(_ id: UUID) -> Data? {
    guard let file = try? directory().appendingPathComponent(id.uuidString + ".resume") else { return nil }
    return try? Data(contentsOf: file)
  }
  static func setResumeData(_ data: Data?, id: UUID) throws {
    let file = try directory().appendingPathComponent(id.uuidString + ".resume")
    if let data { try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
  }
  static func keep(_ file: URL, id: UUID) throws -> URL {
    let target = try directory().appendingPathComponent(id.uuidString + "." + UUID().uuidString + "." + file.pathExtension)
    // A successful previous download must be explicitly removed before replacing it.
    try FileManager.default.moveItem(at: file, to: target)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
    return target
  }
  static func localFile(_ name: String?, id: UUID) -> URL? {
    guard let name, name == (name as NSString).lastPathComponent, name.hasPrefix(id.uuidString + "."),
          let file = try? directory().appendingPathComponent(name), FileManager.default.fileExists(atPath: file.path) else { return nil }
    return file
  }
  static func removeFile(_ file: URL) {
    guard let root = try? directory(), file.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
    try? FileManager.default.removeItem(at: file)
  }
}
