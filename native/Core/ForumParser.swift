import Foundation
import SwiftSoup

struct ForumParser {
  private let unwanted = "script,style,object,embed,input,textarea,select,svg,noscript,.adsbygoogle,.advertisement,.ad-container,.adContainer,.ad-block,.sponsor,[data-ad],[data-ad-slot],[hidden]"
  func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    let doc = try SwiftSoup.parse(source)
    let heading = try doc.select("h1.p-title-value").first()
    let headingTags = try tags(heading, page: url)
    try heading?.select(".labelLink,.label-append").remove()
    let title = text(heading)
    let template = try doc.select("html").first()?.attr("data-template") ?? ""
    let pageTitle = text(try doc.select("title").first()).lowercased()
    if status == 429 { throw ReaderFailure.rateLimit }
    if (try !doc.select("#challenge-running,#challenge-form,.cf-turnstile").isEmpty() && title.isEmpty) ||
        pageTitle.contains("just a moment") || pageTitle.contains("attention required") { throw ReaderFailure.verification }
    if status == 401 || template == "login" || url.path.hasPrefix("/login") { throw ReaderFailure.login }
    if status == 403 { throw ReaderFailure.forbidden }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
    if try template == "error" || !doc.select(".blockMessage--error").isEmpty() {
      throw try doc.select("form[action*=login]").isEmpty() ? ReaderFailure.forbidden : ReaderFailure.login
    }
    try doc.select(unwanted).remove()
    var posts: [ForumPost] = []
    for article in try doc.select("article.message--post") {
      guard let body = try article.select(".message-body .bbWrapper").first() else { continue }
      let time = try article.select(".message-attribution-main time").first()
      let number = try article.select(".message-attribution-opposite a").array().map { text($0) }
        .first { $0.range(of: #"^#[0-9,]+$"#, options: .regularExpression) != nil } ?? ""
      posts.append(ForumPost(id: article.id(), author: text(try article.select(".message-name .username").first()),
                             date: (try time?.attr("datetime")) ?? text(time), number: number, blocks: try parseBody(body, page: url)))
    }
    var seen = Set<String>()
    var threads: [ForumEntry] = []
    let rows = try doc.select(".structItem--thread")
    for row in rows {
      let anchor = try row.select(".structItem-title a").first { !$0.hasClass("labelLink") }
      guard let link = SitePolicy.resolve(try anchor?.attr("href"), from: url, internalOnly: true), seen.insert(link.absoluteString).inserted else { continue }
      threads.append(ForumEntry(title: text(anchor), url: link,
                                subtitle: text(try row.select(".structItem-minor .username").first()),
                                pinned: try !row.select(".structItem-status--sticky").isEmpty(), thumbnail: thumbnail(row, page: url),
                                tags: try tags(row.select(".structItem-title").first(), page: url)))
    }
    var forums: [ForumEntry] = []
    for node in try doc.select(".node") {
      let anchor = try node.select(".node-title a").first()
      guard let link = SitePolicy.resolve(try anchor?.attr("href"), from: url, internalOnly: true), seen.insert(link.absoluteString).inserted else { continue }
      let category = node.parents().first { $0.hasClass("block--category") }
      let sectionAnchor = try category?.select(".u-anchorTarget[id]").first()?.id()
      forums.append(ForumEntry(title: text(anchor), url: link, subtitle: text(try node.select(".node-description").first()), sectionAnchor: sectionAnchor))
    }
    let kind: PageKind
    if !posts.isEmpty || template == "thread_view" { kind = .posts }
    else if !threads.isEmpty || ["forum_view", "watched_threads_list", "search_forum_view"].contains(template) { kind = .threads }
    else if !forums.isEmpty || template == "forum_list" { kind = .forums }
    else { throw ReaderFailure.unsupported }
    if kind == .posts && posts.isEmpty { throw ReaderFailure.unsupported }
    if kind == .threads && !rows.isEmpty() && threads.isEmpty { throw ReaderFailure.unsupported }
    func paging(_ direction: String) throws -> URL? {
      let link = try doc.select(".pageNav-jump--\(direction),.pageNavSimple-el--\(direction),link[rel=\(direction)]").first()
      return SitePolicy.resolve(try link?.attr("href"), from: url, internalOnly: true)
    }
    let next = try paging("next")
    let pageNumber = Int(text(try doc.select(".pageNav-page--current").first())) ?? SitePolicy.pageNumber(url)
    let pageRoot = SitePolicy.pageRoot(url)
    let pageLinks = try doc.select(".pageNav-page a[href],.pageNavSimple-el--last,link[rel=last]").array()
      .compactMap { SitePolicy.resolve(try? $0.attr("href"), from: url, internalOnly: true) }
      .filter { SitePolicy.pageRoot($0) == pageRoot }
    let lastPage = (pageLinks + [next].compactMap { $0 }).max { SitePolicy.pageNumber($0) < SitePolicy.pageNumber($1) }
    let hasLaterPage = next != nil || lastPage.map { SitePolicy.pageNumber($0) > pageNumber } == true
    let maximum = kind == .posts && !hasLaterPage ? posts.compactMap { Int($0.number.dropFirst().replacingOccurrences(of: ",", with: "")) }.max() : nil
    var breadcrumbs: [ForumEntry] = []
    if let trail = try doc.select(".p-breadcrumbs").first() {
      for link in try trail.select("a[href]") {
        guard let target = SitePolicy.resolve(try link.attr("href"), from: url, internalOnly: true), !text(link).isEmpty else { continue }
        breadcrumbs.append(ForumEntry(title: text(link), url: target))
      }
    }
    return ForumPage(url: url, title: title.isEmpty ? "Forums" : title, kind: kind, entries: forums + threads, posts: posts,
                     previous: try paging("prev"), next: next, pageNumber: pageNumber,
                     loggedIn: try doc.select("html").first()?.attr("data-logged-in") == "true",
                     lastPage: lastPage, maximumPostNumber: maximum, breadcrumbs: breadcrumbs, tags: headingTags)
  }
  private func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
  private func tags(_ node: Element?, page: URL) throws -> [ForumTag] {
    guard let node else { return [] }
    var seen = Set<String>()
    return try node.select(".labelLink[href]").array().compactMap { link in
      let title = text(link)
      guard !title.isEmpty, let url = SitePolicy.resolve(try link.attr("href"), from: page, internalOnly: true),
            seen.insert(url.absoluteString + ":" + title).inserted else { return nil }
      return ForumTag(title: title, url: url)
    }
  }
  private func thumbnail(_ row: Element, page: URL) -> URL? {
    guard let cell = try? row.select(".structItem-cell--icon:not(.structItem-cell--iconEnd)").first() else { return nil }
    let nodes = ((try? cell.select(".dcThumbnail img,.dcThumbnail,img").array()) ?? [])
    for node in nodes {
      let style = (try? node.attr("style")) ?? ""
      if let regex = try? NSRegularExpression(pattern: #"(?i)background(?:-image)?\s*:\s*url\(\s*["']?([^"')]+)["']?\s*\)"#),
         let match = regex.firstMatch(in: style, range: NSRange(style.startIndex..., in: style)),
         let range = Range(match.range(at: 1), in: style), let url = thumbnailURL(String(style[range]), page: page) { return url }
      for attribute in ["data-src", "src"] {
        if let url = thumbnailURL(try? node.attr(attribute), page: page) { return url }
      }
    }
    return nil
  }
  private func thumbnailURL(_ value: String?, page: URL) -> URL? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
          let candidate = URL(string: value, relativeTo: page)?.absoluteURL else { return nil }
    if candidate.scheme == "http" {
      guard candidate.port == nil || candidate.port == 80 else { return nil }
      var parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
      parts.scheme = "https"
      parts.port = nil
      return SitePolicy.resolve(parts.url?.absoluteString, from: page)
    }
    return SitePolicy.resolve(candidate.absoluteString, from: page)
  }
  private func ratio(_ node: Element) -> Double? {
    guard let w = Double((try? node.attr("width")) ?? ""), let h = Double((try? node.attr("height")) ?? ""),
          w > 0, h > 0, (w / h).isFinite else { return nil }
    return w / h
  }
  func parseBody(_ root: Element, page: URL) throws -> [BodyBlock] {
    var blocks: [BodyBlock] = []
    var runs: [TextRun] = []
    func flush() {
      if runs.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        blocks.append(BodyBlock(kind: .paragraph, runs: runs))
      }
      runs = []
    }
    func walk(_ node: Node, bold: Bool = false, italic: Bool = false, href: URL? = nil) throws {
      if let node = node as? TextNode {
        runs.append(TextRun(text: node.getWholeText().replacingOccurrences(of: #"[\t\r\n ]+"#, with: " ", options: .regularExpression), bold: bold, italic: italic, url: href))
        return
      }
      guard let node = node as? Element else { return }
      let tag = node.tagName()
      if ["script", "style", "object", "embed", "form", "input", "textarea", "select", "svg", "noscript"].contains(tag) ||
          node.hasAttr("hidden") || node.hasAttr("data-ad") || node.hasAttr("data-ad-slot") ||
          ["advertisement", "ad-container", "adContainer", "ad-block", "adsbygoogle", "sponsor"].contains(where: node.hasClass) { return }
      if node.hasClass("bbCodeBlock--unfurl") {
        flush()
        let anchor = try node.select(".js-unfurl-title a").first()
        if let url = SitePolicy.resolve(try anchor?.attr("href"), from: page) {
          blocks.append(BodyBlock(kind: .link, label: text(anchor).isEmpty ? url.host ?? "Link" : text(anchor), url: url))
        }
        return
      }
      if tag == "img" {
        let alt = try node.attr("alt")
        if node.hasClass("smilie") { runs.append(TextRun(text: alt)); return }
        flush()
        let lazy = try node.attr("data-src")
        if let url = SitePolicy.resolve(lazy.isEmpty ? try node.attr("src") : lazy, from: page) {
          blocks.append(BodyBlock(kind: .image, label: alt.isEmpty ? "Image" : alt, url: url, aspectRatio: ratio(node)))
        }
        return
      }
      if ["iframe", "video", "audio"].contains(tag) {
        flush()
        var candidates = [try node.attr("src"), try node.attr("data-src")]
        if tag != "iframe" { candidates.append(try node.select("source[src]").first()?.attr("src") ?? "") }
        let url = SitePolicy.resolve(candidates.first { !$0.isEmpty }, from: page)
        let poster = try SitePolicy.resolve(node.attr("poster"), from: page) ?? SitePolicy.resolve(node.attr("data-poster"), from: page)
        blocks.append(BodyBlock(kind: .media, label: url?.host ?? "Embedded media", url: url, poster: poster, aspectRatio: ratio(node), direct: tag != "iframe"))
        return
      }
      if tag == "blockquote" || node.hasClass("bbCodeBlock--quote") {
        flush()
        let content = try node.select(".bbCodeBlock-expandContent,.bbCodeBlock-content").first() ?? node
        blocks.append(BodyBlock(kind: .quote, children: try parseBody(content, page: page), label: text(try node.select(".bbCodeBlock-title").first())))
        return
      }
      if node.hasClass("bbCodeSpoiler") || node.hasClass("bbCodeInlineSpoiler") {
        flush()
        let children: [BodyBlock]
        if node.hasClass("bbCodeInlineSpoiler") { children = [BodyBlock(kind: .paragraph, runs: [TextRun(text: text(node))])] }
        else if let content = try node.select(".bbCodeSpoiler-content").first() { children = try parseBody(content, page: page) }
        else { children = [] }
        blocks.append(BodyBlock(kind: .spoiler, children: children, label: "Spoiler"))
        return
      }
      if tag == "pre" { flush(); blocks.append(BodyBlock(kind: .code, label: text(node))); return }
      if tag == "br" { runs.append(TextRun(text: "\n")); return }
      let boundary = ["p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "table", "tr"].contains(tag)
      if boundary { flush() }
      if tag == "li" { runs.append(TextRun(text: "\u{2022} ")) }
      let link = tag == "a" ? SitePolicy.resolve(try node.attr("href"), from: page) : href
      for child in node.getChildNodes() {
        try walk(child, bold: bold || ["b", "strong", "h1", "h2", "h3", "h4"].contains(tag), italic: italic || ["i", "em"].contains(tag), href: link)
      }
      if boundary { flush() }
    }
    for child in root.getChildNodes() { try walk(child) }
    flush()
    return blocks
  }
  static func poster(_ source: String, page: URL) -> URL? {
    guard let doc = try? SwiftSoup.parse(source) else { return nil }
    _ = try? doc.select(".advertisement,.ad-container,.adContainer,.adsbygoogle,[data-ad-slot]").remove()
    let primary = (try? doc.select("video#main-video").array()) ?? []
    let videos = primary.isEmpty ? ((try? doc.select("video").array()) ?? []) : primary
    var candidates: [String] = []
    for video in videos { candidates += [(try? video.attr("poster")) ?? "", (try? video.attr("data-poster")) ?? ""] }
    for selector in ["meta[property=og:image]", "meta[name=twitter:image]"] {
      candidates.append((try? doc.select(selector).first()?.attr("content")) ?? "")
    }
    return candidates.compactMap { SitePolicy.resolve($0, from: page) }.first {
      ($0.port == nil || $0.port == 443) && $0.absoluteString.utf8.count <= 8192
    }
  }
}
