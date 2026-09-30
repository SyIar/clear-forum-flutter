import Foundation

enum FileHost: String, Codable, CaseIterable {
  case bunkr, pixeldrain, fileditch, filester
  var title: String {
    switch self { case .bunkr: return "Bunkr"; case .pixeldrain: return "Pixeldrain"; case .fileditch: return "Fileditch"; case .filester: return "Filester" }
  }
}

struct HostedFileEntry: Identifiable, Hashable {
  let pageURL: URL
  var name: String
  var folder = false
  var size: Int64?
  var mime = ""
  var remoteID: String?
  var id: String { HostedFilePolicy.key(pageURL) }
  var symbol: String {
    folder ? "folder.fill" : mime.hasPrefix("video/") ? "play.rectangle.fill" : mime.hasPrefix("image/") ? "photo" : "doc.fill"
  }
}

struct HostedFileListing {
  let url: URL
  let title: String
  let entries: [HostedFileEntry]
  var expandedAlbum = false
  var pages = 1
}

struct HostedFileRequest {
  let url: URL
  let referer: URL
  let name: String
  var size: Int64?
  var mime = ""
  func accepts(_ target: URL) -> Bool {
    HostedFilePolicy.publicHTTPS(target) && target.host?.lowercased() == url.host?.lowercased() &&
      !["maint.mp4", "maintenance-vid.mp4"].contains(target.lastPathComponent.lowercased())
  }
}

enum HostedFilePolicy {
  static func retryDate(_ value: String?) -> Date {
    let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    return max(Date().addingTimeInterval(60), value.flatMap { format.date(from: $0) }
      ?? Date().addingTimeInterval(value.flatMap(Double.init) ?? 60))
  }
  // Confirmed site aliases, not a wildcard that would trust unrelated domains.
  static let bunkrDomains: Set<String> = Set(["ac", "ax", "black", "cat", "ci", "cr", "fi", "is", "la", "media", "org", "ph", "pk", "ps", "red", "ru", "si", "site", "sk", "su", "to", "ws"].map { "bunkr." + $0 } + ["bunkrr.ru", "bunkrr.su"])
  static func validID(_ value: String) -> Bool {
    value.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil
  }
  static func publicHTTPS(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
          url.port == nil || url.port == 443, url.absoluteString.utf8.count <= 8192,
          let host = url.host?.lowercased(), host.contains("."), !host.contains(":"),
          !["localhost", "local", "internal", "test", "invalid"].contains(host.split(separator: ".").last.map(String.init) ?? ""),
          host.range(of: #"^[0-9.]+$"#, options: .regularExpression) == nil else { return false }
    return true
  }
  static func siteHost(_ url: URL) -> String {
    var host = url.host?.lowercased() ?? ""
    for prefix in ["www.", "app."] { if host.hasPrefix(prefix) { host.removeFirst(prefix.count) } }
    return host
  }
  static func provider(_ url: URL) -> FileHost? {
    guard publicHTTPS(url) else { return nil }
    let host = siteHost(url), parts = url.path.split(separator: "/").map(String.init)
    if bunkrDomains.contains(host), parts.count == 2, ["a", "f", "v", "i", "d"].contains(parts[0]), validID(parts[1]) { return .bunkr }
    if host == "pixeldrain.com", parts.count == 2, ["l", "u"].contains(parts[0]), validID(parts[1]) { return .pixeldrain }
    if host == "filester.me", parts.count == 2, ["d", "f"].contains(parts[0]), validID(parts[1]) { return .filester }
    if host == "fileditchfiles.st", parts.count >= 2, !url.pathExtension.isEmpty { return .fileditch }
    return nil
  }
  static func key(_ url: URL) -> String {
    guard let provider = provider(url) else { return url.absoluteString }
    if provider == .fileditch { return provider.rawValue + ":" + url.path }
    return provider.rawValue + ":" + url.path.split(separator: "/").joined(separator: "/")
  }
  static func isFolder(_ url: URL) -> Bool {
    switch provider(url) {
    case .bunkr: return url.path.hasPrefix("/a/")
    case .pixeldrain: return url.path.hasPrefix("/l/")
    case .filester: return url.path.hasPrefix("/f/")
    default: return false
    }
  }
  static func mime(_ name: String) -> String {
    switch (name as NSString).pathExtension.lowercased() {
    case "mp4", "m4v": return "video/mp4"
    case "webm": return "video/webm"
    case "mov": return "video/quicktime"
    case "mkv": return "video/x-matroska"
    case "mp3": return "audio/mpeg"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "webp": return "image/webp"
    case "pdf": return "application/pdf"
    case "zip": return "application/zip"
    case "torrent": return "application/x-bittorrent"
    default: return "application/octet-stream"
    }
  }
  static func responseError(status: Int, mime: String?, bytes: Int64, expected: Int64?, prefix: Data) -> String? {
    guard status == 200 else { return "The server did not return a complete file (HTTP \(status))." }
    guard bytes > 0, bytes <= GofilePolicy.fileLimit else { return "The file is empty or exceeds the download size limit." }
    if let expected, expected > 0, bytes != expected { return "The downloaded file size is incorrect. Please retry." }
    let type = mime?.lowercased() ?? ""
    let start = String(decoding: prefix.prefix(1024), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["text/html", "application/xhtml+xml", "application/json"].contains(type) || start.hasPrefix("<!doctype html") || start.hasPrefix("<html") || start.hasPrefix("{\"error") {
      return "The server returned a web page or error instead of the file. Open the website to check access."
    }
    return nil
  }
}

enum HostedFileFailure: Error, LocalizedError {
  case unsupported, format, access, missing, limit
  case rateLimited(Date)
  var retryDate: Date? { if case .rateLimited(let date) = self { return date }; return nil }
  var errorDescription: String? {
    switch self {
    case .unsupported: return "This address is not supported by the file browser."
    case .format: return "Could not read the complete file list. Open the website or try refreshing."
    case .access: return "This file needs website access, a password or an account, or has reached its download limit. Open the website to check."
    case .missing: return "This file or folder is no longer available."
    case .limit: return "This collection exceeds the 10,000-item or 20-folder-level limit. Open a smaller folder."
    case .rateLimited: return "The server asked downloads to pause. Wait before continuing; saved files are kept."
    }
  }
}

// Queue discovery and file transfers advance one item at a time, preserving the
// collection hierarchy without overwriting equal or case-colliding filenames.
struct HostedBatchPlan {
  struct Item {
    let entry: HostedFileEntry
    let path: [String]
  }
  private(set) var pending: [Item] = []
  private var seen = Set<String>()
  private var paths = Set<String>()
  private var count = 0
  init(_ listing: HostedFileListing) throws {
    if HostedFilePolicy.isFolder(listing.url) { seen.insert(HostedFilePolicy.key(listing.url)) }
    try append(listing.entries, parent: [])
  }
  mutating func advance() { if !pending.isEmpty { pending.removeFirst() } }
  mutating func expand(_ listing: HostedFileListing) throws {
    guard let current = pending.first, current.entry.folder,
          HostedFilePolicy.key(listing.url) == current.entry.id else { throw HostedFileFailure.format }
    try append(listing.entries, parent: current.path)
    advance()
  }
  private mutating func append(_ entries: [HostedFileEntry], parent: [String]) throws {
    guard count + entries.count <= 10000, parent.count < 20 else { throw HostedFileFailure.limit }
    count += entries.count
    for entry in entries where seen.insert(entry.id).inserted {
      let clean = GofilePolicy.filename(entry.name)
      let ext = (clean as NSString).pathExtension
      let stem = ext.isEmpty ? clean : (clean as NSString).deletingPathExtension
      var name = clean, suffix = 1
      while !paths.insert((parent + [name]).joined(separator: "/").lowercased()).inserted {
        suffix += 1; name = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : "." + ext)
      }
      pending.append(Item(entry: entry, path: parent + [name]))
    }
  }
}
