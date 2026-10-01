import Foundation
import SwiftSoup

struct BookhouseParser {
  func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    guard let route = BookhouseSitePolicy.route(url), source.utf8.count <= 8 * 1024 * 1024 else { throw ReaderFailure.unsupported }
    if status == 429 { throw ReaderFailure.rateLimit }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
    if route.kind == .cursor || route.kind == .replies {
      guard let rows = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]] else { throw ReaderFailure.unsupported }
      return listing(rows, url: url, replies: route.kind == .replies)
    }
    let doc = try SwiftSoup.parse(source)
    if route.kind == .thread { return try novel(doc, source: source, url: url) }
    var page: ForumPage
    if let rows = Self.embeddedJSON("_PageData", in: source) as? [[String: Any]] {
      page = listing(rows, url: url)
    } else {
      // Browser captures and search pages already contain the rendered list.
      // Search pages also contain an unrelated featured list above the results.
      let rows = try doc.select(route.kind == .search ? ".thread-list > li" : ".thread-list > li,.post-list .post-item").array()
      var entries: [ForumEntry] = []
      var seen = Set<String>()
      for row in rows {
        let anchors = try row.select("a[href]").array()
        guard let anchor = anchors.first(where: {
          BookhouseSitePolicy.resolve(try? $0.attr("href"), from: url, internalOnly: true).flatMap(BookhouseSitePolicy.threadKey) != nil
        }), let target = BookhouseSitePolicy.resolve(try anchor.attr("href"), from: url, internalOnly: true),
              let id = BookhouseSitePolicy.threadKey(target), seen.insert(id).inserted else { continue }
        let title = try anchor.text()
        guard !title.isEmpty else { continue }
        let children = row.children().array()
        let author = children.first(where: { $0.tagName() == "font" }).flatMap { try? $0.text() }
          ?? anchors.dropFirst().first.flatMap { try? $0.text() } ?? ""
        let date = children.first(where: { ["i", "time"].contains($0.tagName()) }).flatMap { try? $0.text() } ?? ""
        entries.append(ForumEntry(title: title, url: target, subtitle: author, authorName: author,
                                  postedAt: date.isEmpty ? nil : date))
      }
      let catalogContainer = try doc.select("#d_list").first()
      let searchContainer = route.kind == .search ? try doc.select(".thread-list").first() : nil
      guard !rows.isEmpty || searchContainer != nil || catalogContainer != nil else { throw ReaderFailure.unsupported }
      page = ForumPage(url: url, title: route.kind == .search ? AppText.text("Search results") : AppText.text("Forbidden Library"),
                       kind: .threads, entries: entries, posts: [], pageNumber: BookhouseSitePolicy.pageNumber(url))
    }
    if route.kind == .catalog {
      var seen = Set(page.entries.map(\.id))
      for anchor in try doc.select("#d_gold_list .gold_td a[href]").array() {
        guard let target = BookhouseSitePolicy.resolve(try anchor.attr("href"), from: url, internalOnly: true),
              BookhouseSitePolicy.threadKey(target) != nil, seen.insert(target.absoluteString).inserted else { continue }
        let title = try anchor.text()
        if !title.isEmpty { page.entries.append(ForumEntry(title: title, url: target, pinned: true)) }
      }
      for anchor in try doc.select(".ext_org_title a[href]").array() {
        guard let target = BookhouseSitePolicy.resolve(try anchor.attr("href"), from: url, internalOnly: true),
              BookhouseSitePolicy.route(target)?.kind == .search else { continue }
        page.tags.append(ForumTag(title: try anchor.text(), url: target))
      }
    }
    if route.kind == .search {
      page.title = route.parameters["keywords"] ?? route.parameters["type"] ?? AppText.text("Search results")
      let current = page.pageNumber
      var numbers = [current]
      for anchor in try doc.select(".pagination-bar a[href]").array() {
        guard let target = BookhouseSitePolicy.resolve(try anchor.attr("href"), from: url, internalOnly: true),
              BookhouseSitePolicy.pageRoot(target) == BookhouseSitePolicy.pageRoot(url) else { continue }
        numbers.append(BookhouseSitePolicy.pageNumber(target))
      }
      page.totalPages = numbers.max()
      page.previous = current > 1 ? BookhouseSitePolicy.pageURL(url, number: current - 1) : nil
      page.next = (numbers.max() ?? current) > current ? BookhouseSitePolicy.pageURL(url, number: current + 1) : nil
    }
    return page
  }

  private func listing(_ rows: [[String: Any]], url: URL, replies: Bool = false) -> ForumPage {
    let selected = replies ? rows : rows.filter { Self.string($0["uptid"] ?? $0["rootid"]) == "0" }
    var seen = Set<String>()
    let entries = selected.compactMap { row -> ForumEntry? in
      let id = Self.string(row["tid"])
      guard let target = BookhouseSitePolicy.thread(id), seen.insert(id).inserted else { return nil }
      let title = (try? SwiftSoup.parseBodyFragment(Self.string(row["subject"])).text()) ?? ""
      guard !title.isEmpty else { return nil }
      let author = Self.string(row["username"])
      return ForumEntry(title: title, url: target, subtitle: author, authorID: Self.string(row["uid"]),
                        authorName: author, postedAt: Self.string(row["dateline"]))
    }
    let minimum = entries.compactMap { BookhouseSitePolicy.threadKey($0.url).flatMap(Int64.init) }.min()
    let oldCursor = BookhouseSitePolicy.route(url)?.parameters["mtid"].flatMap(Int64.init)
    let next = !replies && minimum.map { oldCursor == nil || $0 < oldCursor! } == true
      ? minimum.flatMap { BookhouseSitePolicy.cursor(String($0)) } : nil
    return ForumPage(url: url, title: replies ? AppText.text("Replies and continuations") : AppText.text("Forbidden Library"),
                     kind: .threads, entries: entries, posts: [], next: next, pageNumber: 1)
  }

  private func novel(_ doc: Document, source: String, url: URL) throws -> ForumPage {
    guard let body = try doc.select("#content-section,.content-section").first(), let id = BookhouseSitePolicy.threadKey(url) else { throw ReaderFailure.unsupported }
    let metadata = (Self.embeddedJSON("threadInfo", in: source) as? [String: Any]) ?? [:]
    let title = try doc.select("h1.main-title").first()?.text() ?? Self.string(metadata["subject"])
    guard !title.isEmpty else { throw ReaderFailure.unsupported }
    let author = Self.string(metadata["username"])
    let fallbackAuthor = try doc.select(".subtitle-line .sender a").first()?.text() ?? ""
    let byline = try doc.select(".subtitle-line").first()?.text() ?? ""
    let datePattern = #"\b[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}(?:\s+[0-9]{1,2}:[0-9]{2})?"#
    let date = byline.range(of: datePattern, options: .regularExpression).map { String(byline[$0]) } ?? ""
    let blocks = try BookhouseBodyParser().parse(body, page: url)
    let post = ForumPost(id: "bookhouse-" + id, author: author.isEmpty ? fallbackAuthor : author, date: date,
                         number: "", blocks: blocks, authorID: Self.string(metadata["uid"]))
    return ForumPage(url: url, title: title, kind: .posts, entries: [], posts: [post], pageNumber: 1,
                     breadcrumbs: [ForumEntry(title: AppText.text("Forbidden Library"), url: BookhouseSitePolicy.start)])
  }

  private static func string(_ value: Any?) -> String {
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    return ""
  }
  // Extract JSON data only. Never execute supplied scripts or evaluate JS expressions.
  static func embeddedJSON(_ name: String, in source: String) -> Any? {
    let pattern = #"\b(?:const|let|var)\s+"# + NSRegularExpression.escapedPattern(for: name) + #"\s*=\s*"#
    guard let range = source.range(of: pattern, options: .regularExpression) else { return nil }
    let tail = source[range.upperBound...]
    guard let first = tail.first, first == "[" || first == "{" else { return nil }
    var depth = 0; var quoted = false; var escaped = false
    for index in tail.indices {
      let char = tail[index]
      if quoted {
        if escaped { escaped = false }
        else if char == "\\" { escaped = true }
        else if char == "\"" { quoted = false }
      } else if char == "\"" { quoted = true }
      else if char == "[" || char == "{" { depth += 1 }
      else if char == "]" || char == "}" {
        depth -= 1
        if depth == 0 { return try? JSONSerialization.jsonObject(with: Data(tail[...index].utf8)) }
      }
    }
    return nil
  }
}
