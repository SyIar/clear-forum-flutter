import Foundation

enum BookhouseChapterPart: Int, Comparable, Sendable {
  case upper = 1, middle, lower
  init?(_ text: String) {
    switch text {
    case "\u{4E0A}": self = .upper
    case "\u{4E2D}": self = .middle
    case "\u{4E0B}": self = .lower
    default: return nil
    }
  }
  static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct BookhouseChapterTitle: Equatable {
  // Stable internal numbers keep extras distinct from regular chapters, even
  // when the regular catalog grows. Display and slider positions decode them.
  static let maximumNumber = 100_000
  static let extraOffset = maximumNumber
  static func isExtra(_ number: Int) -> Bool { number > extraOffset }
  static func localNumber(_ number: Int) -> Int { isExtra(number) ? number - extraOffset : number }
  static func validRange(first: Int, last: Int) -> Bool {
    // Persisted extra chapters use offset numbers; validate their local range
    // without allowing a publication to span regular and extra chapters.
    first > 0 && last >= first && isExtra(first) == isExtra(last) &&
      (1...maximumNumber).contains(localNumber(last))
  }
  static func searchTitle(_ title: String) -> String {
    let text = title.precomposedStringWithCompatibilityMapping
    let primary = text.prefix { $0 != "(" }.trimmingCharacters(in: .whitespacesAndNewlines)
    return primary.isEmpty ? title : primary
  }
  let book: String
  let first: Int
  let last: Int
  let part: BookhouseChapterPart?
  static func normalized(_ text: String) -> String {
    text.precomposedStringWithCompatibilityMapping
      .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
  }
  static func number(_ text: String) -> Int? {
    let value = text.precomposedStringWithCompatibilityMapping
    if let number = Int(value), (1...maximumNumber).contains(number) { return number }
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
    return (1...maximumNumber).contains(result) ? result : nil
  }
  static let numberPattern = "[0-9\u{96F6}\u{3007}\u{4E00}\u{4E8C}\u{4E24}\u{4E09}\u{56DB}\u{4E94}\u{516D}\u{4E03}\u{516B}\u{4E5D}\u{5341}\u{767E}\u{5343}\u{4E07}]+"
  init?(_ source: String) {
    let text = source.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = "^[\u{3010}\u{300A}\\[]?([^\u{3011}\u{300B}\\]]+)[\u{3011}\u{300B}\\]]\\s*(?:\\(\\s*)?(?:(\u{756A}\u{5916})\\s*)?(?:\u{7B2C}\\s*)?(" + Self.numberPattern + ")(?:\\s*[-~\u{2013}\u{2014}\u{81F3}]\\s*(" + Self.numberPattern + "))?\\s*(?:([\u{4E0A}\u{4E2D}\u{4E0B}])\\s*)?(?:\u{7AE0}|\\))(?:\\s*\\(\\s*([\u{4E0A}\u{4E2D}\u{4E0B}])\\s*\\))?"
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let name = Range(match.range(at: 1), in: text), let start = Range(match.range(at: 3), in: text),
          let first = Self.number(String(text[start])) else { return nil }
    let last = Range(match.range(at: 4), in: text).flatMap { Self.number(String(text[$0])) } ?? first
    let book = String(text[name]).trimmingCharacters(in: .whitespacesAndNewlines)
    let part = [5, 6].compactMap { Range(match.range(at: $0), in: text).flatMap { BookhouseChapterPart(String(text[$0])) } }.first
    guard !book.isEmpty, book.count <= 100, first <= last else { return nil }
    guard part == nil || first == last else { return nil }
    let offset = match.range(at: 2).location == NSNotFound ? 0 : Self.extraOffset
    self.book = book; self.first = first + offset; self.last = last + offset; self.part = part
  }
}

struct BookhouseChapter: Codable, Identifiable, Equatable, Sendable {
  var id: String { url.absoluteString }
  let url: URL
  let title: String
  let first: Int
  let last: Int
  let part: BookhouseChapterPart?
  init(url: URL, title: String, first: Int, last: Int) {
    self.url = url; self.title = title; self.first = first; self.last = last
    part = BookhouseChapterTitle(title)?.part
  }
  private enum CodingKeys: String, CodingKey { case url, title, first, last }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(url: try values.decode(URL.self, forKey: .url), title: try values.decode(String.self, forKey: .title),
      first: try values.decode(Int.self, forKey: .first), last: try values.decode(Int.self, forKey: .last))
  }
}
struct BookhouseReadingPosition: Codable, Equatable, Sendable {
  let url: URL
  let chapter: Int
  let paragraph: Int
}
enum BookhouseAuthorSource: String, Codable, Sendable { case title, postingAccount }
struct BookhouseFollowedBook: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  var author: String
  var authorSource: BookhouseAuthorSource?
  // Account IDs apply only when no literary author is declared in the title.
  var authorID: String?
  let followedAt: Date
  let seed: URL
  var chapters: [BookhouseChapter]
  var position: BookhouseReadingPosition?
  var maximumRead: Int?
  var checkedAt: Date?
  var attemptedAt: Date?
  var acknowledgedMaximum: Int
  var acknowledgedRegularMaximum: Int?
  var maximumReadRegular: Int?
  var catalogVersion: Int? = 3
  var latestChapter: Int { chapters.map(\.last).max() ?? 0 }
  var latestRegularChapter: Int { chapters.filter { !BookhouseChapterTitle.isExtra($0.first) }.map(\.last).max() ?? 0 }
  var latestExtraChapter: Int { chapters.filter { BookhouseChapterTitle.isExtra($0.first) }.map { BookhouseChapterTitle.localNumber($0.last) }.max() ?? 0 }
  var sliderChapterCount: Int { latestRegularChapter + latestExtraChapter }
  var searchTitle: String { BookhouseChapterTitle.searchTitle(title) }
  // Longer queries can return no results even when matching publications exist.
  var catalogKeywords: String { String(searchTitle.prefix(7)) }
  func sliderPosition(for chapter: Int) -> Int {
    BookhouseChapterTitle.isExtra(chapter) ? latestRegularChapter + BookhouseChapterTitle.localNumber(chapter) : chapter
  }
  func chapterNumber(at position: Int) -> Int {
    position > latestRegularChapter ? BookhouseChapterTitle.extraOffset + position - latestRegularChapter : position
  }
  @discardableResult mutating func migrateCatalog() -> Bool {
    guard catalogVersion != 3 else { return false }
    catalogVersion = 3
    // Recheck old, possibly seed-only catalogs without discarding reading state.
    checkedAt = nil; attemptedAt = nil
    return true
  }
  var updated: Bool {
    let regularBaseline = acknowledgedRegularMaximum ?? (BookhouseChapterTitle.isExtra(acknowledgedMaximum) ? 0 : acknowledgedMaximum)
    let regularRead = maximumReadRegular ?? (BookhouseChapterTitle.isExtra(maximumRead ?? 0) ? 0 : maximumRead ?? 0)
    return latestChapter > max(acknowledgedMaximum, maximumRead ?? 0) || latestRegularChapter > max(regularBaseline, regularRead)
  }
  var resumeURL: URL { position?.url ?? seed }

  init?(entry: ForumEntry, at date: Date = Date()) {
    let identity = BookhouseTitlePresentation(title: entry.title, postingAuthor: entry.authorName ?? "")
    let author = identity.author
    guard let parsed = BookhouseChapterTitle(entry.title),
          !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let url = BookhouseSitePolicy.threadRoot(entry.url) else { return nil }
    id = UUID().uuidString; title = parsed.book; self.author = author
    authorSource = identity.literaryAuthor == nil ? .postingAccount : .title
    authorID = authorSource == .postingAccount ? entry.authorID : nil; followedAt = date; seed = url
    chapters = [BookhouseChapter(url: url, title: entry.title, first: parsed.first, last: parsed.last)]
    acknowledgedMaximum = parsed.last
    acknowledgedRegularMaximum = BookhouseChapterTitle.isExtra(parsed.first) ? 0 : parsed.last
  }
  @discardableResult mutating func migrateAuthor() -> Bool {
    guard authorSource == nil else { return false }
    let source = chapters.first { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(seed) }?.title
    if let source, let name = BookhouseTitlePresentation(title: source, postingAuthor: "").literaryAuthor {
      adoptLiteraryAuthor(name)
    } else { authorSource = .postingAccount }
    return true
  }
  private mutating func adoptLiteraryAuthor(_ name: String) {
    author = name; authorSource = .title; authorID = nil
    // A previous account-only catalog is incomplete and must be rebuilt once.
    checkedAt = nil; attemptedAt = nil
    chapters = chapters.filter { matchesTitle($0.title) }
  }
  private func matchesTitle(_ source: String) -> Bool {
    guard let parsed = BookhouseChapterTitle(source),
          BookhouseChapterTitle.normalized(BookhouseChapterTitle.searchTitle(parsed.book)) == BookhouseChapterTitle.normalized(searchTitle) else { return false }
    let candidate = BookhouseChapterTitle.normalized(parsed.book)
    let original = BookhouseChapterTitle.normalized(title)
    let primary = BookhouseChapterTitle.normalized(searchTitle)
    // An omitted subtitle is fine; different explicit subtitles are not aliases.
    guard candidate == original || candidate == primary || original == primary else { return false }
    guard authorSource == .title else { return true }
    let name = BookhouseTitlePresentation(title: source, postingAuthor: "").literaryAuthor
    return name.map { BookhouseChapterTitle.normalized($0) == BookhouseChapterTitle.normalized(author) } ?? false
  }
  @discardableResult mutating func verifySeed(_ page: ForumPage) -> Bool {
    guard BookhouseSitePolicy.threadKey(page.url) == BookhouseSitePolicy.threadKey(seed), accepts(page),
          let post = page.posts.first else { return false }
    if authorSource != .title {
      if let name = BookhouseTitlePresentation(title: page.title, postingAuthor: "").literaryAuthor,
         let index = chapters.firstIndex(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(seed) }) {
        let old = chapters[index]
        chapters[index] = BookhouseChapter(url: old.url, title: page.title, first: old.first, last: old.last)
        adoptLiteraryAuthor(name)
      } else { authorID = post.authorID }
    }
    return true
  }
  mutating func mergeCatalog(_ entries: [ForumEntry], verifiedBy snapshot: Self, checkedAt: Date) {
    guard snapshot.id == id, snapshot.followedAt == followedAt else { return }
    if snapshot.authorSource == .title, authorSource != .title {
      for chapter in snapshot.chapters {
        if let index = chapters.firstIndex(where: { $0.id == chapter.id }) { chapters[index] = chapter }
        else { chapters.append(chapter) }
      }
      adoptLiteraryAuthor(snapshot.author)
    }
    if authorSource != .title { authorID = snapshot.authorID }
    merge(entries, checkedAt: checkedAt, searchResults: true)
  }
  func matches(_ entry: ForumEntry) -> Bool {
    guard matchesTitle(entry.title), BookhouseSitePolicy.threadKey(entry.url) != nil else { return false }
    return matchesAuthor(title: entry.title, postingAuthor: entry.authorName ?? "", accountID: entry.authorID)
  }
  func matchesCatalogResult(_ entry: ForumEntry) -> Bool {
    // Only use this for results of this book's validated catalog search.
    guard BookhouseChapterTitle(entry.title) != nil, BookhouseSitePolicy.threadKey(entry.url) != nil else { return false }
    return matchesAuthor(title: entry.title, postingAuthor: entry.authorName ?? "", accountID: entry.authorID)
  }
  private func matchesAuthor(title: String, postingAuthor: String, accountID: String?) -> Bool {
    if authorSource == .title {
      let name = BookhouseTitlePresentation(title: title, postingAuthor: "").literaryAuthor
      return name.map { BookhouseChapterTitle.normalized($0) == BookhouseChapterTitle.normalized(author) } ?? false
    }
    guard BookhouseChapterTitle.normalized(postingAuthor) == BookhouseChapterTitle.normalized(author) else { return false }
    if let authorID, let accountID { return authorID == accountID }
    return true
  }
  func accepts(_ page: ForumPage) -> Bool {
    guard page.kind == .posts, let post = page.posts.first,
          let chapter = chapters.first(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(page.url) }),
          let source = BookhouseChapterTitle(chapter.title), let actual = BookhouseChapterTitle(page.title),
          BookhouseChapterTitle.normalized(source.book) == BookhouseChapterTitle.normalized(actual.book),
          source.first == actual.first, source.last == actual.last else { return false }
    return matchesAuthor(title: page.title, postingAuthor: post.author, accountID: post.authorID) &&
      (authorSource == .title || authorID == nil || post.authorID == authorID)
  }
  func chapter(containing number: Int, excluding url: URL? = nil, preferLastPart: Bool = false) -> BookhouseChapter? {
    // Prefer the narrowest publication when chapter bundles overlap.
    chapters.filter { ($0.first...$0.last).contains(number) && $0.url != url }.min {
      if $0.last - $0.first != $1.last - $1.first { return $0.last - $0.first < $1.last - $1.first }
      if let left = $0.part, let right = $1.part, left != right { return preferLastPart ? left > right : left < right }
      if $0.part != $1.part { return $0.part == nil }
      return $0.id < $1.id
    }
  }
  func adjacentPart(to publication: BookhouseChapter, edge: ReaderEdge) -> BookhouseChapter? {
    guard let part = publication.part else { return nil }
    let candidates = chapters.filter {
      $0.first == publication.first && $0.last == publication.last && $0.part.map { edge == .next ? $0 > part : $0 < part } == true
    }.sorted { $0.part == $1.part ? $0.id < $1.id : $0.part! < $1.part! }
    return edge == .next ? candidates.first : candidates.last
  }
  func adjacentChapter(to publication: BookhouseChapter, boundary: Int, edge: ReaderEdge) -> BookhouseChapter? {
    if let part = adjacentPart(to: publication, edge: edge) { return part }
    if let next = chapter(containing: boundary + (edge == .next ? 1 : -1), excluding: publication.url, preferLastPart: edge == .previous) { return next }
    if edge == .next, boundary == latestRegularChapter {
      return chapter(containing: BookhouseChapterTitle.extraOffset + 1)
    }
    if edge == .previous, boundary == BookhouseChapterTitle.extraOffset + 1, latestRegularChapter > 0 {
      return chapter(containing: latestRegularChapter, preferLastPart: true)
    }
    return nil
  }
  mutating func merge(_ entries: [ForumEntry], checkedAt: Date, searchResults: Bool = false) {
    var collected = Dictionary(chapters.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for entry in entries where searchResults ? matchesCatalogResult(entry) : matches(entry) {
      guard let parsed = BookhouseChapterTitle(entry.title), let url = BookhouseSitePolicy.threadRoot(entry.url) else { continue }
      collected[url.absoluteString] = BookhouseChapter(url: url, title: entry.title, first: parsed.first, last: parsed.last)
    }
    chapters = collected.values.sorted {
      if $0.first != $1.first { return $0.first < $1.first }
      if $0.part != $1.part { return ($0.part?.rawValue ?? 0) < ($1.part?.rawValue ?? 0) }
      return $0.id < $1.id
    }
    // The initial catalog establishes the update baseline without marking it read.
    if self.checkedAt == nil { acknowledgedMaximum = latestChapter; acknowledgedRegularMaximum = latestRegularChapter }
    self.checkedAt = checkedAt
  }
  mutating func record(url: URL, chapter: Int, paragraph: Int) {
    guard paragraph >= 0, let item = chapters.first(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(url) }),
          (item.first...item.last).contains(chapter) else { return }
    position = BookhouseReadingPosition(url: item.url, chapter: chapter, paragraph: paragraph)
    maximumRead = max(maximumRead ?? 0, chapter)
    if !BookhouseChapterTitle.isExtra(chapter) { maximumReadRegular = max(maximumReadRegular ?? 0, chapter) }
  }
}

struct BookhouseChapterAnchors {
  let byParagraph: [Int: Int]
  init(blocks: [BodyBlock], chapter: BookhouseChapter) {
    let extra = BookhouseChapterTitle.isExtra(chapter.first)
    let prefix = extra ? "(?:\u{756A}\u{5916}\\s*(?:\u{7B2C}\\s*)?|\u{7B2C}\\s*)" : "\u{7B2C}\\s*"
    let suffix = extra ? "(?:\\s*\u{7AE0})?(?:\\s|[\u{FF1A}:\u{3001}.]|$)" : "\\s*\u{7AE0}(?:\\s|[\u{FF1A}:\u{3001}.]|$)"
    let pattern = "^\\s*" + prefix + "(" + BookhouseChapterTitle.numberPattern + ")" + suffix
    let regex = try? NSRegularExpression(pattern: pattern)
    var values: [Int: Int] = [:], seen = Set<Int>()
    var last = chapter.first - 1
    for (index, block) in blocks.enumerated() where block.kind == .paragraph {
      let text = block.runs.map(\.text).joined().precomposedStringWithCompatibilityMapping
      guard text.count <= 120, let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text), let raw = BookhouseChapterTitle.number(String(text[range])) else { continue }
      let number = raw + (extra ? BookhouseChapterTitle.extraOffset : 0)
      guard (chapter.first...chapter.last).contains(number), number >= last, seen.insert(number).inserted else { continue }
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
  func followedBook(for entry: ForumEntry) -> BookhouseFollowedBook? {
    readingBooks.first { book in
      if book.matches(entry) { return true }
      guard book.matchesCatalogResult(entry), let title = BookhouseChapterTitle(entry.title) else { return false }
      return book.chapters.contains { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(entry.url) } ||
        BookhouseChapterTitle.normalized(String(BookhouseChapterTitle.searchTitle(title.book).prefix(7))) ==
          BookhouseChapterTitle.normalized(book.catalogKeywords)
    }
  }
  func followedBook(at url: URL) -> BookhouseFollowedBook? {
    guard let key = BookhouseSitePolicy.threadKey(url) else { return nil }
    return readingBooks.first { book in book.chapters.contains { BookhouseSitePolicy.threadKey($0.url) == key } }
  }
}
