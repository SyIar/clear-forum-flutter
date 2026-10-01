import Foundation

// Catalog-only presentation; the source title and posting account remain intact.
struct BookhouseTitlePresentation: Equatable {
  let title: String
  let author: String
  let tags: [String]

  init(title source: String, postingAuthor: String) {
    // The author clause can end at a category tag or at the end of the title.
    let authorPattern = "\u{4F5C}\u{8005}\\s*[:\u{FF1A}]\\s*([^\u{300E}\u{300F}\\r\\n]+?)(?=\\s*(?:\u{300E}|$))"
    let tagPattern = "\u{300E}([^\u{300E}\u{300F}\\r\\n]+)\u{300F}"
    var display = source
    var extractedAuthor = postingAuthor
    if let expression = try? NSRegularExpression(pattern: authorPattern),
       let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
       let nameRange = Range(match.range(at: 1), in: source),
       let clauseRange = Range(match.range, in: source) {
      let name = source[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty {
        extractedAuthor = name
        display.removeSubrange(clauseRange)
      }
    }
    var categories: [String] = []
    if let expression = try? NSRegularExpression(pattern: tagPattern) {
      for match in expression.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
        guard let range = Range(match.range(at: 1), in: source) else { continue }
        let tag = source[range].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tag.isEmpty, !categories.contains(tag) { categories.append(tag) }
      }
      display = expression.stringByReplacingMatches(in: display, range: NSRange(display.startIndex..., in: display), withTemplate: "")
    }
    display = display.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.title = display.isEmpty ? source : display
    self.author = extractedAuthor
    self.tags = display.isEmpty ? [] : categories
  }
}
