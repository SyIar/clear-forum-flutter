import Foundation

enum GofilePolicy {
  static let base = URL(string: "https://gofile.io")!
  static let fileLimit: Int64 = 8 * 1024 * 1024 * 1024
  static func validID(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 128 && value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
  }
  static func website(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && ["gofile.io", "www.gofile.io"].contains(url.host?.lowercased() ?? "") &&
      url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
  }
  static func fileURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
          url.port == nil || url.port == 443, let host = url.host?.lowercased(),
          host.hasSuffix(".gofile.io"), host != "api.gofile.io" else { return false }
    let parts = url.path.split(separator: "/")
    return parts.count >= 4 && parts[0] == "download" && parts[1] == "web" && validID(String(parts[2]))
  }
  static func pageURL(_ url: URL) -> URL? {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil,
          url.port == nil || url.port == 443 || url.port == 80 else { return nil }
    let parts = url.path.split(separator: "/")
    let id: String
    if ["gofile.io", "www.gofile.io"].contains(url.host?.lowercased() ?? ""), parts.count == 2, parts[0] == "d" {
      id = String(parts[1])
    } else if fileURL(url) { id = String(parts[2]) }
    else { return nil }
    guard validID(id) else { return nil }
    return base.appendingPathComponent("d").appendingPathComponent(id)
  }
  static func page(_ url: URL, number: Int) -> URL {
    var value = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    value.queryItems = number > 1 ? [URLQueryItem(name: "page", value: String(number))] : nil
    return value.url!
  }
  static func filename(_ raw: String) -> String {
    let bad = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
    var value = String(raw.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined().prefix(160))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    while value.utf8.count > 220 { value.removeLast() }
    return value.isEmpty || value == "." || value == ".." ? "Download" : value
  }
  static func responseError(status: Int, url: URL, mime: String?, expectedMIME: String?, bytes: Int64,
                            expectedBytes: Int64?, prefix: Data, limit: Int64 = fileLimit) -> String? {
    guard status == 200 else { return "The server did not return a complete file (HTTP \(status))." }
    guard fileURL(url) else { return "Gofile returned a web page. Refresh the folder to restore the download session." }
    guard bytes <= limit else { return "This file exceeds the download size limit." }
    if let expectedBytes, expectedBytes != bytes { return "The downloaded size does not match the file. Refresh the folder and try again." }
    let mime = mime?.lowercased() ?? ""
    let expected = expectedMIME?.lowercased() ?? ""
    let text = String(decoding: prefix.prefix(512), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if expected != "text/html" && expected != "application/xhtml+xml" &&
        (["text/html", "application/xhtml+xml"].contains(mime) || text.hasPrefix("<!doctype html") || text.hasPrefix("<html")) {
      return "Gofile returned an HTML page instead of the file. Refresh the folder and try again."
    }
    if mime == "application/json" && expected != "application/json" { return "Gofile returned an error response instead of the file." }
    return nil
  }
}

struct GofileEntry: Identifiable, Hashable {
  let id: String
  let name: String
  let folder: Bool
  let size: Int64?
  let mime: String
  let link: URL?
  let thumbnail: URL?
  let unavailable: Bool
  var pageURL: URL { GofilePolicy.base.appendingPathComponent("d").appendingPathComponent(id) }
  var isVideo: Bool { mime.hasPrefix("video/") || mime.hasPrefix("audio/") }
  var symbol: String { folder ? "folder.fill" : mime.hasPrefix("image/") ? "photo" : isVideo ? "play.rectangle" : "doc" }
}

struct GofileListing {
  let id: String
  let title: String
  let entries: [GofileEntry]
  let page: Int
  let pages: Int
  static func parse(_ payload: [String: Any], requested: URL, page: Int) throws -> Self {
    guard payload["contentId"] as? String == requested.lastPathComponent,
          (payload["page"] as? NSNumber)?.intValue == page else { throw GofileFailure.stale }
    let status = payload["status"] as? String
    let http = (payload["httpStatus"] as? NSNumber)?.intValue ?? 200
    if http == 429 || status == "error-rateLimit" {
      throw GofileFailure.rateLimited(Date().addingTimeInterval(max(1, (payload["retryAfter"] as? NSNumber)?.doubleValue ?? 60)))
    }
    if status == "error-notFound" || http == 404 { throw GofileFailure.notFound }
    if status == "error-notPremium" { throw GofileFailure.premium }
    guard (200..<300).contains(http), status == "ok", let data = payload["data"] as? [String: Any] else { throw GofileFailure.website }
    if data["canAccess"] as? Bool == false {
      if data["passwordRequired"] as? Bool == true { throw GofileFailure.password(wrong: data["passwordWrong"] as? Bool == true) }
      if data["expired"] as? Bool == true { throw GofileFailure.expired }
      throw GofileFailure.access
    }
    guard let type = data["type"] as? String, ["file", "folder"].contains(type) else { throw GofileFailure.website }
    let rows = data["children"] as? [[String: Any]] ?? []
    guard rows.count <= 1000 else { throw GofileFailure.website }
    var seen = Set<String>()
    let entries = rows.compactMap { row -> GofileEntry? in
      guard let id = row["id"] as? String, GofilePolicy.validID(id), seen.insert(id).inserted,
            let type = row["type"] as? String, ["file", "folder"].contains(type) else { return nil }
      func address(_ key: String) -> URL? {
        guard let value = row[key] as? String, value.utf8.count <= 8192, let url = URL(string: value), GofilePolicy.fileURL(url),
              url.path.split(separator: "/").dropFirst(2).first.map(String.init) == id else { return nil }
        return url
      }
      let bytes = (row["size"] as? NSNumber)?.int64Value
      return GofileEntry(id: id, name: String((row["name"] as? String ?? "File").prefix(512)), folder: type == "folder",
                         size: bytes.flatMap { $0 >= 0 ? $0 : nil }, mime: String((row["mimetype"] as? String ?? "").prefix(128)).lowercased(),
                         link: address("link"), thumbnail: address("thumbnail"),
                         unavailable: row["isFrozen"] as? Bool == true || row["overloaded"] as? Bool == true || row["canAccess"] as? Bool == false)
    }
    let count = (payload["totalPages"] as? NSNumber)?.intValue ?? page
    let id = (data["id"] as? String).flatMap { GofilePolicy.validID($0) ? $0 : nil } ?? requested.lastPathComponent
    return Self(id: id, title: String((data["name"] as? String ?? "Gofile").prefix(512)), entries: entries, page: page, pages: max(page, min(100000, count)))
  }
}

enum GofileFailure: Error, LocalizedError, Equatable {
  case stale, website, access, notFound, expired, premium, unavailable
  case password(wrong: Bool)
  case rateLimited(Date)
  var title: String {
    switch self {
    case .password: return "Password required"
    case .notFound: return "Content not found"
    case .expired: return "Link expired"
    case .access: return "Private content"
    case .premium: return "Premium access required"
    case .rateLimited: return "Downloads paused"
    case .unavailable: return "File unavailable"
    default: return "Could not load content"
    }
  }
  var symbol: String {
    switch self {
    case .password, .access, .premium: return "lock.fill"
    case .expired, .rateLimited: return "clock"
    case .notFound: return "folder.badge.questionmark"
    default: return "exclamationmark.triangle"
    }
  }
  var retryDate: Date? { if case .rateLimited(let date) = self { return date }; return nil }
  var needsPassword: Bool { if case .password = self { return true }; return false }
  var errorDescription: String? {
    switch self {
    case .stale: return "The folder changed while it was loading. Please refresh."
    case .website: return "Could not read this folder. Open the website to check access, then return to Files."
    case .access: return "The owner has not made this content public. Ask the owner for access."
    case .password(let wrong): return wrong ? "Incorrect password. Please try again." : "Enter the password shared by the owner."
    case .notFound: return "This content was removed, or the link is incorrect."
    case .expired: return "The owner set an expiration date for this link. Ask for a new link."
    case .premium: return "Gofile requires Premium access for this content."
    case .unavailable: return "This file is temporarily unavailable or restricted by Gofile."
    case .rateLimited: return "Gofile asked this device to slow down. Wait before resuming; completed files are safe."
    }
  }
}
