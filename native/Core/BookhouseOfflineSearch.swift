import Foundation

struct BookhouseOfflineMatch: Identifiable, Hashable, Sendable {
  let bookID: String
  let bookTitle: String
  let author: String
  let publicationTitle: String
  let url: URL
  let chapter: Int
  let paragraph: Int
  let snippet: String
  let query: String
  var id: String { "\(bookID):\(url.absoluteString):\(paragraph)" }
}

enum BookhouseOfflineSearch {
  struct Document: Sendable {
    let book: BookhouseFollowedBook
    let chapter: BookhouseChapter
    let file: URL
  }
  struct Result: Sendable {
    var matches: [BookhouseOfflineMatch] = []
    var truncated = false
    var unreadablePages = 0
  }
  static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

  // A snapshot of immutable cache files can be searched away from the UI thread.
  // Eviction during a search is tolerated; search never fetches or touches LRU dates.
  static func search(_ source: String, documents: [Document], limit: Int = 200) throws -> Result {
    let query = source.trimmingCharacters(in: .whitespacesAndNewlines)
    var result = Result()
    guard !query.isEmpty else { return result }
    for document in documents {
      try Task.checkCancellation()
      let page: ForumPage
      do { page = try JSONDecoder().decode(ForumPage.self, from: Data(contentsOf: document.file)) }
      catch { result.unreadablePages += 1; continue }
      guard document.book.accepts(page), BookhouseSitePolicy.threadKey(page.url) == BookhouseSitePolicy.threadKey(document.chapter.url),
            let blocks = page.posts.first?.blocks else { continue }
      let anchors = BookhouseChapterAnchors(blocks: blocks, chapter: document.chapter)
      for (index, block) in blocks.enumerated() {
        try Task.checkCancellation()
        let body = text(block)
        guard let range = body.range(of: query, options: options) else { continue }
        guard result.matches.count < max(1, limit) else { result.truncated = true; return result }
        let lower = body.index(range.lowerBound, offsetBy: -45, limitedBy: body.startIndex) ?? body.startIndex
        let upper = body.index(range.upperBound, offsetBy: 75, limitedBy: body.endIndex) ?? body.endIndex
        let snippet = (lower > body.startIndex ? "\u{2026}" : "") + String(body[lower..<upper]) + (upper < body.endIndex ? "\u{2026}" : "")
        result.matches.append(BookhouseOfflineMatch(bookID: document.book.id, bookTitle: document.book.title,
          author: document.book.author, publicationTitle: document.chapter.title, url: document.chapter.url,
          chapter: anchors.chapter(at: index, fallback: document.chapter.first), paragraph: index, snippet: snippet, query: query))
      }
    }
    return result
  }
  private static func text(_ block: BodyBlock) -> String {
    guard ![.image, .media, .purchase].contains(block.kind) else { return "" }
    return ([block.runs.map(\.text).joined()] + block.children.map(text)).filter { !$0.isEmpty }.joined(separator: "\n")
  }
}
