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
  // Rounded page labels are presentation only, never expected transfer bytes.
  var reportedSize: String?
  var id: String { HostedFilePolicy.key(pageURL) }
  var sizeDescription: String {
    if let size, size >= 0 { return ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    return reportedSize ?? AppText.text("Size unknown")
  }
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
    guard HostedFilePolicy.publicHTTPS(target),
          !["maint.mp4", "maintenance-vid.mp4"].contains(target.lastPathComponent.lowercased()) else { return false }
    if target.host?.lowercased() == url.host?.lowercased() { return true }
    // Direct mirrors may redirect the same resource across domain suffixes.
    guard let host = HostedFilePolicy.hostProvider(url), [.pixeldrain, .fileditch].contains(host),
          HostedFilePolicy.hostProvider(target) == host else { return false }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ==
      URLComponents(url: target, resolvingAgainstBaseURL: false)?.percentEncodedPath
  }
}

enum HostedFilePolicy {
  static func retryDate(_ value: String?) -> Date {
    let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
    format.timeZone = TimeZone(secondsFromGMT: 0); format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
    return max(Date().addingTimeInterval(60), value.flatMap { format.date(from: $0) }
      ?? Date().addingTimeInterval(value.flatMap(Double.init) ?? 60))
  }
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
    if let prefix = ["www.", "app."].first(where: { host.hasPrefix($0) }) { host.removeFirst(prefix.count) }
    return host
  }
  // Match the complete brand label plus one suffix, not a hostname substring.
  // This selects a parser; requests still carry no forum cookies or credentials.
  static func hostProvider(_ url: URL) -> FileHost? {
    guard publicHTTPS(url) else { return nil }
    let host = siteHost(url), labels = host.split(separator: ".")
    if host == "pixeldra.in" { return .pixeldrain }
    guard labels.count == 2, labels[1].range(of: #"^[a-z]{2,63}$"#, options: .regularExpression) != nil else { return nil }
    switch labels[0] {
    case "bunkr", "bunkrr": return .bunkr
    case "pixeldrain": return .pixeldrain
    case "filester": return .filester
    case "fileditchfiles": return .fileditch
    default: return nil
    }
  }
  static func filesterServer(_ url: URL) -> Bool {
    guard publicHTTPS(url), let host = url.host?.lowercased(),
          ["", "/"].contains(url.path), url.query == nil, url.fragment == nil else { return false }
    // The public download API also returns this dedicated CDN for stored files.
    return host == "fsc2.cdn.cr" ||
      host.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+filester\.[a-z]{2,63}$"#, options: .regularExpression) != nil
  }
  static func filesterFile(_ value: String) -> Bool {
    value.range(of: #"\A[A-Za-z0-9_-]{1,128}(?:\.[A-Za-z0-9]{1,16}){0,3}\z"#, options: .regularExpression) != nil
  }
  static func acceptsMetadataRedirect(from original: URL, to target: URL, provider: FileHost) -> Bool {
    guard publicHTTPS(target) else { return false }
    if target.host?.lowercased() == original.host?.lowercased() { return true }
    return hostProvider(original) == provider && hostProvider(target) == provider
  }
  static func provider(_ url: URL) -> FileHost? {
    guard let host = hostProvider(url) else { return nil }
    let parts = url.path.split(separator: "/").map(String.init)
    if host == .bunkr, parts.count == 2, ["a", "f", "v", "i", "d"].contains(parts[0]), validID(parts[1]) { return .bunkr }
    if host == .pixeldrain, parts.count == 2, ["l", "u"].contains(parts[0]), validID(parts[1]) { return .pixeldrain }
    if host == .filester, parts.count == 2, ["d", "f"].contains(parts[0]), validID(parts[1]) { return .filester }
    if host == .fileditch, parts.count >= 2, parts[0] != "api", !url.pathExtension.isEmpty { return .fileditch }
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
    guard status == 200 else { return AppText.format("The server did not return a complete file (HTTP %@).", String(describing: status)) }
    guard bytes > 0, bytes <= GofilePolicy.fileLimit else { return AppText.text("The file is empty or exceeds the download size limit.") }
    if let expected, expected > 0, bytes != expected { return AppText.text("The downloaded file size is incorrect. Please retry.") }
    let type = mime?.lowercased() ?? ""
    let start = String(decoding: prefix.prefix(1024), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["text/html", "application/xhtml+xml", "application/json"].contains(type) || start.hasPrefix("<!doctype html") || start.hasPrefix("<html") || start.hasPrefix("{\"error") {
      return AppText.text("The server returned a web page or error instead of the file. Open the website to check access.")
    }
    return nil
  }
}

enum HostedFileFailure: Error, LocalizedError {
  case unsupported, format, downloadLink, access, missing, limit
  case rateLimited(Date)
  var retryDate: Date? { if case .rateLimited(let date) = self { return date }; return nil }
  var errorDescription: String? {
    switch self {
    case .unsupported: return AppText.text("This address is not supported by the file browser.")
    case .format: return AppText.text("Could not read the complete file list. Open the website or try refreshing.")
    case .downloadLink: return AppText.text("Could not resolve the download address. Refresh or open the original website.")
    case .access: return AppText.text("This file needs website access, a password or an account, or has reached its download limit. Open the website to check.")
    case .missing: return AppText.text("This file or folder is no longer available.")
    case .limit: return AppText.text("This file list is too large or has too many folder levels. Open a smaller folder.")
    case .rateLimited: return AppText.text("The server asked downloads to pause. Wait before continuing; saved files are kept.")
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
