import Foundation

struct BookhouseReadingParagraph: Identifiable {
  let url: URL
  let index: Int
  let chapter: Int
  let block: BodyBlock
  var id: String { Self.id(url: url, index: index) }
  static func id(url: URL, index: Int) -> String {
    "novel-\(BookhouseSitePolicy.threadKey(url) ?? url.absoluteString)-\(index)"
  }
}

struct BookhouseReadingSlice {
  let page: ForumPage
  let publication: BookhouseChapter
  let range: Range<Int>
  let first: Int
  let last: Int
  let anchors: BookhouseChapterAnchors
  var paragraphs: [BookhouseReadingParagraph] {
    guard let blocks = page.posts.first?.blocks else { return [] }
    return range.map { index in
      BookhouseReadingParagraph(url: publication.url, index: index,
        chapter: anchors.chapter(at: index, fallback: first), block: blocks[index])
    }
  }
}

// Keep publication boundaries separate from chapter boundaries. Bundles may
// overlap; trim only at a verified heading, never repeat or guess missing text.
struct BookhouseReadingWindow {
  private(set) var slices: [BookhouseReadingSlice] = []
  let countLimit: Int
  let costLimit: Int
  init(countLimit: Int = 5, costLimit: Int = 16 * 1024 * 1024) {
    self.countLimit = max(2, countLimit); self.costLimit = max(1, costLimit)
  }
  var paragraphs: [BookhouseReadingParagraph] { slices.flatMap(\.paragraphs) }
  func paragraph(id: String?) -> BookhouseReadingParagraph? {
    guard let id else { return nil }
    return paragraphs.first { $0.id == id }
  }
  func page(containing id: String?) -> ForumPage? {
    guard let id else { return nil }
    return slices.first { $0.paragraphs.contains { $0.id == id } }?.page
  }
  func target(_ edge: ReaderEdge, book: BookhouseFollowedBook) -> BookhouseChapter? {
    guard let boundary = edge == .previous ? slices.first : slices.last else { return nil }
    return book.chapter(containing: edge == .previous ? boundary.first - 1 : boundary.last + 1,
      excluding: boundary.publication.url)
  }
  @discardableResult mutating func reset(_ page: ForumPage, book: BookhouseFollowedBook) -> Bool {
    guard let slice = slice(page, book: book) else { return false }
    slices = [slice]
    return true
  }
  @discardableResult mutating func insert(_ page: ForumPage, at edge: ReaderEdge, book: BookhouseFollowedBook) -> Bool {
    guard let target = target(edge, book: book),
          BookhouseSitePolicy.threadKey(target.url) == BookhouseSitePolicy.threadKey(page.url),
          let incoming = slice(page, book: book), let boundary = edge == .previous ? slices.first : slices.last else { return false }
    var range = incoming.range
    var first = incoming.first, last = incoming.last
    if edge == .next {
      let number = boundary.last + 1
      guard (first...last).contains(number) else { return false }
      if first < number {
        guard let start = incoming.anchors.paragraph(for: number) else { return false }
        range = start..<range.upperBound
      }
      first = number
    } else {
      let number = boundary.first - 1
      guard (first...last).contains(number) else { return false }
      if last > number {
        guard let end = incoming.anchors.paragraph(for: number + 1) else { return false }
        range = range.lowerBound..<end
      }
      last = number
    }
    guard !range.isEmpty else { return false }
    let joined = BookhouseReadingSlice(page: page, publication: incoming.publication, range: range,
      first: first, last: last, anchors: incoming.anchors)
    let existingIDs = Set(paragraphs.map(\.id))
    guard !joined.paragraphs.contains(where: { existingIDs.contains($0.id) }) else { return false }
    if edge == .previous { slices.insert(joined, at: 0) } else { slices.append(joined) }
    return true
  }
  // Called only after scrolling settles. Protect the visible publication and
  // the newly joined edge, so eviction cannot immediately undo a successful load.
  mutating func trim(keeping id: String?, preserving edge: ReaderEdge) {
    var cost = slices.reduce(0) { $0 + $1.page.estimatedCacheCost }
    while slices.count > 2, slices.count > countLimit || cost > costLimit {
      let index = edge == .next ? 0 : slices.count - 1
      if slices[index].paragraphs.contains(where: { $0.id == id }) { break }
      cost -= slices.remove(at: index).page.estimatedCacheCost
    }
  }
  private func slice(_ page: ForumPage, book: BookhouseFollowedBook) -> BookhouseReadingSlice? {
    guard book.accepts(page), let blocks = page.posts.first?.blocks, !blocks.isEmpty,
          let publication = book.chapters.first(where: {
            BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(page.url)
          }) else { return nil }
    let anchors = BookhouseChapterAnchors(blocks: blocks, chapter: publication)
    return BookhouseReadingSlice(page: page, publication: publication, range: blocks.indices,
      first: anchors.byParagraph.values.min() ?? publication.first,
      last: anchors.byParagraph.values.max() ?? publication.last, anchors: anchors)
  }
}
