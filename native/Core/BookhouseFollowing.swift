import Foundation

struct BookhouseChapterTitle: Equatable {
  let book: String
  let first: Int
  let last: Int
  static func normalized(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping
      .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
  }
  static func number(_ text: String) -> Int? {
    let value = text.precomposedStringWithCompatibilityMapping
    if let number = Int(value), (1...100_000).contains(number) { return number }
    let digits: [Character: Int] = ["\u{96F6}": 0, "\u{3007}": 0, "\u{4E00}": 1, "\u{4E8C}": 2,
      "\u{4E24}": 2, "\u{4E09}": 3, "\u{56DB}": 4, "\u{4E94}": 5, "\u{516D}": 6,
      "\u{4E03}": 7, "\u{516B}": 8, "\u{4E5D}": 9]
    let units: [Character: Int] = ["\u{5341}": 10, "\u{767E}": 100, "\u{5343}": 1000, "\u{4E07}": 10_000]
    guard !value.isEmpty else { return nil }
    if value.allSatisfy({ digits[$0] != nil }) {
      return number(value.map { String(digits[$0]!) }.joined())
    }
    var total = 0, section = 0, digit = 0
    for char in value {
      if let value = digits[char] { digit = value }
      else if let unit = units[char] {
        if unit == 10_000 { total += (section + digit) * unit; section = 0 }
        else { section += max(1, digit) * unit }
        digit = 0
      } else { return nil }
    }
    let result = total + section + digit
    return (1...100_000).contains(result) ? result : nil
  }
  static let numberPattern = "[0-9\u{96F6}\u{3007}\u{4E00}\u{4E8C}\u{4E24}\u{4E09}\u{56DB}\u{4E94}\u{516D}\u{4E03}\u{516B}\u{4E5D}\u{5341}\u{767E}\u{5343}\u{4E07}]+"
  init?(_ source: String) {
    let text = source.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = "^[\u{3010}\u{300A}\\[]([^\u{3011}\u{300B}\\]]+)[\u{3011}\u{300B}\\]]\\s*(?:\u{7B2C}|\\()?\\s*(" + Self.numberPattern + ")(?:\\s*[-~\u{2013}\u{2014}\u{81F3}]\\s*(" + Self.numberPattern + "))?\\s*(?:\u{7AE0}|\\))"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let name = Range(match.range(at: 1), in: text), let start = Range(match.range(at: 2), in: text),
          let first = Self.number(String(text[start])) else { return nil }
    let last = Range(match.range(at: 3), in: text).flatMap { Self.number(String(text[$0])) } ?? first
    let book = String(text[name]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !book.isEmpty, book.count <= 100, first <= last else { return nil }
    self.book = book; self.first = first; self.last = last
  }
}

struct BookhouseChapter: Codable, Identifiable, Equatable {
  var id: String { url.absoluteString }
  let url: URL
  let title: String
  let first: Int
  let last: Int
}
struct BookhouseReadingPosition: Codable, Equatable {
  let url: URL
  let chapter: Int
  let paragraph: Int
}
struct BookhouseFollowedBook: Codable, Identifiable, Equatable {
  let id: String
  let title: String
  // Match the source posting account, never the catalog's extracted literary author.
  let author: String
  var authorID: String?
  let followedAt: Date
  let seed: URL
  var chapters: [BookhouseChapter]
  var position: BookhouseReadingPosition?
  var maximumRead: Int?
  var checkedAt: Date?
  var acknowledgedMaximum: Int
  var latestChapter: Int { chapters.map(\.last).max() ?? 0 }
  var updated: Bool { latestChapter > max(acknowledgedMaximum, maximumRead ?? 0) }
  var resumeURL: URL { position?.url ?? seed }

  init?(entry: ForumEntry, at date: Date = Date()) {
    guard let parsed = BookhouseChapterTitle(entry.title), let author = entry.authorName,
          !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let url = BookhouseSitePolicy.threadRoot(entry.url) else { return nil }
    id = UUID().uuidString; title = parsed.book; self.author = author
    authorID = entry.authorID; followedAt = date; seed = url
    chapters = [BookhouseChapter(url: url, title: entry.title, first: parsed.first, last: parsed.last)]
    acknowledgedMaximum = parsed.last
  }
  func matches(_ entry: ForumEntry) -> Bool {
    guard let parsed = BookhouseChapterTitle(entry.title),
          BookhouseChapterTitle.normalized(parsed.book) == BookhouseChapterTitle.normalized(title),
          BookhouseChapterTitle.normalized(entry.authorName ?? "") == BookhouseChapterTitle.normalized(author),
          BookhouseSitePolicy.threadKey(entry.url) != nil else { return false }
    if let authorID, let id = entry.authorID { return authorID == id }
    return true
  }
  func accepts(_ page: ForumPage) -> Bool {
    guard page.kind == .posts, let post = page.posts.first,
          chapters.contains(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(page.url) }),
          let parsed = BookhouseChapterTitle(page.title),
          BookhouseChapterTitle.normalized(parsed.book) == BookhouseChapterTitle.normalized(title),
          BookhouseChapterTitle.normalized(post.author) == BookhouseChapterTitle.normalized(author) else { return false }
    return authorID == nil || post.authorID == authorID
  }
  func chapter(containing number: Int, excluding url: URL? = nil) -> BookhouseChapter? {
    // Prefer the narrowest publication when chapter bundles overlap.
    chapters.filter { ($0.first...$0.last).contains(number) && $0.url != url }.min {
      if $0.last - $0.first != $1.last - $1.first { return $0.last - $0.first < $1.last - $1.first }
      return $0.id < $1.id
    }
  }
  mutating func merge(_ entries: [ForumEntry], checkedAt: Date) {
    var collected = Dictionary(chapters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for entry in entries where matches(entry) {
      guard let parsed = BookhouseChapterTitle(entry.title), let url = BookhouseSitePolicy.threadRoot(entry.url) else { continue }
      collected[url.absoluteString] = BookhouseChapter(url: url, title: entry.title, first: parsed.first, last: parsed.last)
    }
    chapters = collected.values.sorted { $0.first == $1.first ? $0.id < $1.id : $0.first < $1.first }
    // The initial catalog establishes the update baseline without marking it read.
    if self.checkedAt == nil { acknowledgedMaximum = latestChapter }
    self.checkedAt = checkedAt
  }
  mutating func record(url: URL, chapter: Int, paragraph: Int) {
    guard paragraph >= 0, let item = chapters.first(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(url) }),
          (item.first...item.last).contains(chapter) else { return }
    position = BookhouseReadingPosition(url: item.url, chapter: chapter, paragraph: paragraph)
    maximumRead = max(maximumRead ?? 0, chapter)
  }
}

struct BookhouseChapterAnchors {
  let byParagraph: [Int: Int]
  init(blocks: [BodyBlock], chapter: BookhouseChapter) {
    let pattern = "^\\s*\u{7B2C}\\s*(" + BookhouseChapterTitle.numberPattern + ")\\s*\u{7AE0}(?:\\s|[\u{FF1A}:\u{3001}.]|$)"
    let regex = try? NSRegularExpression(pattern: pattern)
    var values: [Int: Int] = [:], seen = Set<Int>()
    var last = chapter.first - 1
    for (index, block) in blocks.enumerated() where block.kind == .paragraph {
      let text = block.runs.map(\.text).joined().precomposedStringWithCompatibilityMapping
      guard text.count <= 120, let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text), let number = BookhouseChapterTitle.number(String(text[range])),
            (chapter.first...chapter.last).contains(number), number >= last, seen.insert(number).inserted else { continue }
      values[index] = number; last = number
    }
    byParagraph = values
  }
  func paragraph(for chapter: Int) -> Int? { byParagraph.first(where: { $0.value == chapter })?.key }
  func chapter(at paragraph: Int, fallback: Int) -> Int {
    byParagraph.keys.filter { $0 <= paragraph }.max().flatMap { byParagraph[$0] } ?? fallback
  }
}

extension LibraryDocument {
  var readingBooks: [BookhouseFollowedBook] { followedBooks.values.sorted { $0.followedAt > $1.followedAt } }
  func followedBook(for entry: ForumEntry) -> BookhouseFollowedBook? { readingBooks.first { $0.matches(entry) } }
}
