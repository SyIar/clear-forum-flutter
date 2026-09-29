import Foundation

enum SouthTextLinks {
  // Keep Unicode sentence punctuation and invisible separators out of a URL.
  private static let pattern = try! NSRegularExpression(
    pattern: #"(?<![A-Za-z0-9_/@])https?://[^\s\p{C}<>"`\u2018\u2019\u201C\u201D\u3001\u3002\u3008\u3009\u300A\u300B\u300C\u300D\u3010\u3011\uFF01\uFF08\uFF09\uFF0C\uFF1A\uFF1B\uFF1F]+"#,
    options: [.caseInsensitive])

  static func detect(in runs: [TextRun], excluding excluded: Set<Int> = []) -> [TextRun] {
    var result: [TextRun] = []
    var pending: [TextRun] = []
    func flush() { result += link(pending); pending = [] }
    for (index, run) in runs.enumerated() {
      if run.url != nil || run.emoticon != nil || excluded.contains(index) {
        flush()
        result.append(run)
      } else { pending.append(run) }
    }
    flush()
    return result
  }

  // This is for user-tapped navigation only, never authenticated reader/media
  // requests. Preserve external HTTP links instead of silently changing hosts.
  static func destination(_ value: String, from page: URL) -> URL? {
    guard value.utf8.count <= 8192, !value.contains("\\"),
          value.range(of: #"%(?![0-9A-Fa-f]{2})"#, options: .regularExpression) == nil,
          let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(),
          ["http", "https"].contains(scheme), let host = parts.host, !host.isEmpty,
          host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
          parts.user == nil, parts.password == nil,
          parts.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
    var normalized = parts
    normalized.scheme = scheme
    guard let url = normalized.url else { return nil }
    if let local = SouthSitePolicy.resolve(url.absoluteString, from: page), SouthSitePolicy.sameOrigin(local) { return local }
    return url
  }

  private struct Link { let range: NSRange; let url: URL }
  private static func link(_ runs: [TextRun]) -> [TextRun] {
    let text = runs.map(\.text).joined()
    let links = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> Link? in
      guard match.range.length <= 8192, let range = Range(match.range, in: text) else { return nil }
      let address = trimmed(String(text[range]))
      guard let url = destination(address, from: SouthSitePolicy.base) else { return nil }
      return Link(range: NSRange(location: match.range.location, length: address.utf16.count), url: url)
    }
    guard !links.isEmpty else { return runs }
    var result: [TextRun] = []
    var offset = 0
    var linkIndex = 0
    for run in runs {
      let source = run.text as NSString
      var position = 0
      while position < source.length {
        let absolute = offset + position
        while linkIndex < links.count, NSMaxRange(links[linkIndex].range) <= absolute { linkIndex += 1 }
        let current = linkIndex < links.count ? links[linkIndex] : nil
        let inside = current.map { NSLocationInRange(absolute, $0.range) } ?? false
        let boundary = current.map { inside ? NSMaxRange($0.range) : $0.range.location } ?? offset + source.length
        let end = min(source.length, boundary - offset)
        var part = run
        part.text = source.substring(with: NSRange(location: position, length: end - position))
        part.url = inside ? current?.url : nil
        result.append(part)
        position = end
      }
      offset += source.length
    }
    return result
  }
  private static func trimmed(_ value: String) -> String {
    var result = value
    let opening: [Character: Character] = [")": "(", "]": "[", "}": "{"]
    var counts: [Character: Int] = [:]
    for character in result where "()[]{}".contains(character) { counts[character, default: 0] += 1 }
    while let last = result.last {
      if ".,;:!?'".contains(last) { result.removeLast(); continue }
      if let open = opening[last], counts[last, default: 0] > counts[open, default: 0] {
        counts[last, default: 0] -= 1
        result.removeLast(); continue
      }
      break
    }
    return result
  }
}
