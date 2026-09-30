import Foundation
import SwiftSoup

struct ReaderDiagnosticSnapshot {
  let id: UUID
  let address: String
  var events: [String] = []
  var html = ""
  var report: String { (["Reader diagnostics", address] + events).joined(separator: "\n") }
}

enum ReaderDiagnostics {
  // Diagnostic exports contain page content, but never cookie headers, entered
  // form values, script bodies or authentication query parameters.
  static func mediaSummary(_ source: String, page: ForumPage) -> String {
    guard source.utf8.count <= 8 * 1024 * 1024, let doc = try? SwiftSoup.parse(source) else {
      return "Image comparison unavailable"
    }
    let responseImages = (try? doc.select("img").size()) ?? 0
    let attachments = (try? doc.select(".tpc_content [id^=att_] img").size()) ?? 0
    var images = 0
    var emoticons = 0
    func count(_ blocks: [BodyBlock]) {
      for block in blocks {
        if block.kind == .image { images += 1 }
        emoticons += block.runs.filter { $0.emoticon != nil }.count
        count(block.children)
      }
    }
    for post in page.posts { count(post.blocks) }
    return "Response images: \(responseImages); South attachment images: \(attachments); parsed post images: \(images); inline emoticons: \(emoticons)"
  }
  static func htmlExport(_ sanitized: String) -> String {
    "--- SANITIZED PAGE HTML (\(sanitized.utf8.count) UTF-8 bytes) ---\n" + sanitized +
      "\n--- END SANITIZED PAGE HTML ---"
  }
  static func address(_ raw: String) -> String {
    guard var parts = URLComponents(string: raw) else { return "[invalid URL]" }
    parts.user = nil; parts.password = nil
    if parts.query?.contains("=") == true {
      let allowed: Set<String> = ["tid", "fid", "uid", "page", "type", "action", "act", "app", "p", "mtid"]
      parts.queryItems = parts.queryItems?.map {
        URLQueryItem(name: $0.name, value: allowed.contains($0.name.lowercased()) ? $0.value : "[redacted]")
      }
    }
    parts.fragment = nil
    return parts.string ?? "[invalid URL]"
  }
  static func html(_ source: String) -> String {
    guard source.utf8.count <= 8 * 1024 * 1024, let doc = try? SwiftSoup.parse(source) else { return "[source unavailable]" }
    do {
      try doc.select("script,style,textarea,select,object,embed,meta,link,iframe,svg,noscript").remove()
      let allowed: Set<String> = ["id", "class", "name", "type", "href", "src", "data-src", "data-original", "data-full-src",
                                  "data-full-url", "data-url", "width", "height", "colspan", "rowspan", "loading", "referrerpolicy"]
      let addresses: Set<String> = ["href", "src", "data-src", "data-original", "data-full-src", "data-full-url", "data-url"]
      for element in try doc.select("*").array() {
        let attributes = element.getAttributes()?.asList() ?? []
        for attribute in attributes {
          let key = attribute.getKey()
          if !allowed.contains(key) { try element.removeAttr(key) }
          else if addresses.contains(key) {
            let raw = attribute.getValue()
            if raw.lowercased().hasPrefix("javascript:") || raw.lowercased().hasPrefix("data:") { try element.removeAttr(key) }
            else { try element.attr(key, address(raw)) }
          }
        }
      }
      let result = try doc.outerHtml()
      let limit = 1_000_000
      if result.utf8.count <= limit { return result }
      return String(decoding: result.utf8.prefix(limit), as: UTF8.self) + "\n<!-- diagnostic source truncated -->"
    } catch { return "[source sanitizing failed]" }
  }
}
