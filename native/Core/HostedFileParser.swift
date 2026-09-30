import Foundation
import SwiftSoup

enum HostedFileParser {
  static func fileditchSize(_ data: Data) throws -> Int64? {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HostedFileFailure.format }
    if let status = json["status"] as? Bool {
      guard status else { throw HostedFileFailure.missing }
      guard let size = json["size"] as? NSNumber, size.int64Value >= 0 else { throw HostedFileFailure.format }
      return size.int64Value
    }
    return nil
  }
  static func pixeldrain(_ data: Data, url: URL) throws -> HostedFileListing {
    guard HostedFilePolicy.provider(url) == .pixeldrain,
          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw HostedFileFailure.format }
    guard json["success"] as? Bool != false else {
      if json["value"] as? String == "not_found" { throw HostedFileFailure.missing }
      throw HostedFileFailure.access
    }
    let rows: [[String: Any]]
    if HostedFilePolicy.isFolder(url) {
      guard let files = json["files"] as? [[String: Any]] else { throw HostedFileFailure.format }
      rows = files
    } else { rows = [json] }
    guard rows.count <= 10000 else { throw HostedFileFailure.limit }
    var seen = Set<String>()
    var entries: [HostedFileEntry] = []
    for row in rows {
      guard let id = row["id"] as? String, HostedFilePolicy.validID(id), let name = row["name"] as? String else { throw HostedFileFailure.format }
      if !seen.insert(id).inserted { continue }
      let page = URL(string: "/u/\(id)", relativeTo: url)!.absoluteURL
      entries.append(HostedFileEntry(pageURL: page, name: name, size: (row["size"] as? NSNumber)?.int64Value,
                                    mime: (row["mime_type"] as? String) ?? HostedFilePolicy.mime(name)))
    }
    return HostedFileListing(url: url, title: (json["title"] as? String) ?? entries.first?.name ?? "Pixeldrain", entries: entries)
  }

  static func bunkrAlbum(_ html: String, url: URL) throws -> HostedFileListing {
    guard HostedFilePolicy.provider(url) == .bunkr, HostedFilePolicy.isFolder(url) else { throw HostedFileFailure.unsupported }
    let document = try SwiftSoup.parse(html, url.absoluteString)
    let scripts = try document.select("script").array().map { $0.data() }.joined(separator: "\n")
    guard let array = assignedArray("window.albumFiles", in: scripts) else { throw HostedFileFailure.format }
    let objects = try objectLiterals(array)
    guard objects.count <= 10000 else { throw HostedFileFailure.limit }
    var seen = Set<String>()
    var entries: [HostedFileEntry] = []
    for object in objects {
      let fields = try literalFields(object)
      guard let slug = decodedString(fields["slug"]), HostedFilePolicy.validID(slug),
            let name = decodedString(fields["original"]),
            let id = fields["id"], id.range(of: #"^[0-9]{1,20}$"#, options: .regularExpression) != nil,
            let page = URL(string: "/f/" + slug, relativeTo: url)?.absoluteURL else { throw HostedFileFailure.format }
      if !seen.insert(slug).inserted { continue }
      let size = fields["size"].flatMap(Int64.init)
      entries.append(HostedFileEntry(pageURL: page, name: name, size: size, mime: HostedFilePolicy.mime(name), remoteID: id))
    }
    let title = try document.select("h1").first()?.text() ?? "Bunkr"
    return HostedFileListing(url: url, title: title, entries: entries)
  }

  static func bunkrFile(_ html: String, url: URL) throws -> (HostedFileEntry, URL?) {
    guard HostedFilePolicy.provider(url) == .bunkr else { throw HostedFileFailure.unsupported }
    let document = try SwiftSoup.parse(html, url.absoluteString)
    guard let node = try document.select("[data-file-id]").first() else { throw HostedFileFailure.format }
    let id = try node.attr("data-file-id")
    guard id.range(of: #"^[0-9]{1,20}$"#, options: .regularExpression) != nil else { throw HostedFileFailure.format }
    let title = try document.select("h1").first()?.text() ?? "File"
    var album: URL?
    // Related-file cards are only a preview. The heading is the authoritative album link.
    for link in try document.select("h2 a[href]").array() {
      if let target = URL(string: try link.attr("href"), relativeTo: url)?.absoluteURL,
         HostedFilePolicy.provider(target) == .bunkr, HostedFilePolicy.isFolder(target) { album = target; break }
    }
    return (HostedFileEntry(pageURL: url, name: title, mime: HostedFilePolicy.mime(title), remoteID: id), album)
  }

  static func filester(_ html: String, url: URL) throws -> HostedFileListing {
    guard HostedFilePolicy.provider(url) == .filester else { throw HostedFileFailure.unsupported }
    let document = try SwiftSoup.parse(html, url.absoluteString)
    let title = try document.select("h1").first()?.text() ?? "Filester"
    if !HostedFilePolicy.isFolder(url) {
      guard try document.select("#fileTitle").first() != nil else { throw HostedFileFailure.format }
      var entry = HostedFileEntry(pageURL: url, name: title, mime: HostedFilePolicy.mime(title))
      for label in try document.select("#detailsContent span").array() where try label.text().lowercased() == "size" {
        if let value = try label.nextElementSibling()?.text() { entry.reportedSize = sizeLabel(value) }
      }
      return HostedFileListing(url: url, title: title, entries: [entry])
    }
    guard try document.select("#filesGrid, #subfoldersGrid").first() != nil else { throw HostedFileFailure.format }
    var seen = Set<String>(), entries: [HostedFileEntry] = []
    for card in try document.select("#filesGrid .file-item, #subfoldersGrid .subfolder-item").array() {
      let raw = try card.attr("href").isEmpty ? card.select("a[href]").first()?.attr("href") : card.attr("href")
      let path = try raw ?? capture(#"window\.location\.href\s*=\s*['"](/[df]/[A-Za-z0-9_-]+)['"]"#, in: card.attr("onclick"))
      guard let path, let target = URL(string: path, relativeTo: url)?.absoluteURL,
            HostedFilePolicy.provider(target) == .filester else { throw HostedFileFailure.format }
      guard HostedFilePolicy.key(target) != HostedFilePolicy.key(url), seen.insert(HostedFilePolicy.key(target)).inserted else { continue }
      let name = try card.attr("data-name").isEmpty ? card.select(".file-name, .folder-name").text() : card.attr("data-name")
      let size = try Int64(card.attr("data-size"))
      entries.append(HostedFileEntry(pageURL: target, name: name.isEmpty ? target.lastPathComponent : name,
                                    folder: HostedFilePolicy.isFolder(target), size: size, mime: HostedFilePolicy.mime(name),
                                    reportedSize: sizeLabel(try card.select(".file-size").text())))
    }
    guard entries.count <= 10000 else { throw HostedFileFailure.limit }
    let pageCount = try document.select("#loadAllPagesBtn").first()?.attr("data-total")
    let pages = pageCount.flatMap(Int.init) ?? 1
    guard (1...200).contains(pages) else { throw HostedFileFailure.limit }
    return HostedFileListing(url: url, title: title, entries: entries, pages: pages)
  }

  static func filesterDownload(_ data: Data, entry: HostedFileEntry, download: Bool = true) throws -> HostedFileRequest {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let file = json["file"] as? String, HostedFilePolicy.validID(file),
          let token = json["token"] as? String, !token.isEmpty, token.utf8.count <= 8192,
          let base = URL(string: (json["server"] as? String) ?? "https://cn1.filester.me"),
          HostedFilePolicy.filesterServer(base) else { throw HostedFileFailure.format }
    var url = URLComponents(url: base.appendingPathComponent("v2").appendingPathComponent(file), resolvingAgainstBaseURL: false)!
    let name = (json["name"] as? String) ?? entry.name
    url.queryItems = [URLQueryItem(name: "token", value: token)]
    if download { url.queryItems! += [URLQueryItem(name: "download", value: "true"), URLQueryItem(name: "n", value: name)] }
    guard let target = url.url else { throw HostedFileFailure.format }
    return HostedFileRequest(url: target, referer: entry.pageURL, name: name, size: entry.size, mime: entry.mime)
  }

  static func bunkrDownload(_ data: Data, entry: HostedFileEntry) throws -> HostedFileRequest {
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], var value = json["url"] as? String else { throw HostedFileFailure.format }
    if json["encrypted"] as? Bool == true {
      guard let timestamp = (json["timestamp"] as? NSNumber)?.int64Value, timestamp > 0,
            let bytes = Data(base64Encoded: value), bytes.count <= 8192 else { throw HostedFileFailure.format }
      let key = Array("SECRET_KEY_\(timestamp / 3600)".utf8)
      let decoded = bytes.enumerated().map { $0.element ^ key[$0.offset % key.count] }
      guard let address = String(bytes: decoded, encoding: .utf8) else { throw HostedFileFailure.format }
      value = address
    }
    guard let url = URL(string: value), HostedFilePolicy.publicHTTPS(url),
          !["maint.mp4", "maintenance-vid.mp4"].contains(url.lastPathComponent.lowercased()),
          let id = entry.remoteID, HostedFilePolicy.validID(id) else { throw HostedFileFailure.format }
    return HostedFileRequest(url: url, referer: URL(string: "https://get.bunkrr.su/file/\(id)")!, name: entry.name, size: entry.size, mime: entry.mime)
  }

  private static func capture(_ pattern: String, in value: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
          let range = Range(match.range(at: 1), in: value) else { return nil }
    return String(value[range])
  }
  private static func sizeLabel(_ value: String) -> String? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.range(of: #"^[0-9]+(?:[.,][0-9]+)*\s*(?:bytes?|[KMGTPE]?i?B)$"#, options: [.regularExpression, .caseInsensitive]) != nil ? text : nil
  }
  private static func decodedString(_ literal: String?) -> String? {
    guard let literal, let data = literal.replacingOccurrences(of: "\\'", with: "'").data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? String
  }
  private static func literalFields(_ object: String) throws -> [String: String] {
    var cursor = object.index(after: object.startIndex), fields: [String: String] = [:]
    let end = object.index(before: object.endIndex)
    while cursor < end {
      while cursor < end, object[cursor].isWhitespace || object[cursor] == "," { cursor = object.index(after: cursor) }
      if cursor == end { break }
      let keyStart = cursor
      while cursor < end, object[cursor] != ":" { cursor = object.index(after: cursor) }
      guard cursor < end else { throw HostedFileFailure.format }
      let key = object[keyStart..<cursor].trimmingCharacters(in: .whitespacesAndNewlines)
      guard key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil, fields[key] == nil else { throw HostedFileFailure.format }
      cursor = object.index(after: cursor)
      while cursor < end, object[cursor].isWhitespace { cursor = object.index(after: cursor) }
      let start = cursor
      guard cursor < end else { throw HostedFileFailure.format }
      if object[cursor] == "\"" {
        cursor = object.index(after: cursor)
        var escaped = false, closed = false
        while cursor < end {
          let character = object[cursor]; cursor = object.index(after: cursor)
          if escaped { escaped = false }
          else if character == "\\" { escaped = true }
          else if character == "\"" { closed = true; break }
        }
        guard closed else { throw HostedFileFailure.format }
      } else {
        while cursor < end, object[cursor] != "," { cursor = object.index(after: cursor) }
      }
      fields[key] = object[start..<cursor].trimmingCharacters(in: .whitespacesAndNewlines)
      while cursor < end, object[cursor].isWhitespace { cursor = object.index(after: cursor) }
      guard cursor == end || object[cursor] == "," else { throw HostedFileFailure.format }
    }
    return fields
  }
  private static func assignedArray(_ variable: String, in source: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: variable) + #"\s*=\s*(\[)"#),
          let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          let start = Range(match.range(at: 1), in: source)?.lowerBound else { return nil }
    return balanced(source, from: start, opening: "[", closing: "]").map { String(source[$0]) }
  }
  private static func balanced(_ source: String, from start: String.Index, opening: Character, closing: Character) -> Range<String.Index>? {
    var depth = 0, quote: Character?, escaped = false
    for index in source[start...].indices {
      let c = source[index]
      if escaped { escaped = false; continue }
      if let active = quote {
        if c == "\\" { escaped = true } else if c == active { quote = nil }
        continue
      }
      if c == "\"" || c == "'" { quote = c; continue }
      if c == opening { depth += 1 }
      if c == closing { depth -= 1; if depth == 0 { return start..<source.index(after: index) } }
    }
    return nil
  }
  private static func objectLiterals(_ array: String) throws -> [String] {
    var cursor = array.index(after: array.startIndex), objects: [String] = []
    let end = array.index(before: array.endIndex)
    while cursor < end {
      if array[cursor].isWhitespace || array[cursor] == "," { cursor = array.index(after: cursor); continue }
      guard array[cursor] == "{", let object = balanced(array, from: cursor, opening: "{", closing: "}"), object.upperBound <= end else { throw HostedFileFailure.format }
      objects.append(String(array[object]))
      guard objects.count <= 10000 else { throw HostedFileFailure.limit }
      cursor = object.upperBound
    }
    return objects
  }
}
