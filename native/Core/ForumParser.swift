import Foundation
import SwiftSoup

struct ForumParser {
  private let unwanted = "script,style,object,embed,input,textarea,select,svg,noscript,.adsbygoogle,.advertisement,.ad-container,.adContainer,.ad-block,.sponsor,[data-ad],[data-ad-slot],[hidden]"
  func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    let doc = try SwiftSoup.parse(source)
    let title = text(try doc.select("h1.p-title-value").first())
    let template = try doc.select("html").first()?.attr("data-template") ?? ""
    let pageTitle = text(try doc.select("title").first()).lowercased()
    if status == 429 { throw ReaderFailure.rateLimit }
    if (try !doc.select("#challenge-running,#challenge-form,.cf-turnstile").isEmpty() && title.isEmpty) ||
        pageTitle.contains("just a moment") || pageTitle.contains("attention required") { throw ReaderFailure.verification }
    if status == 401 || template == "login" || url.path.hasPrefix("/login") { throw ReaderFailure.login }
    if status == 403 { throw ReaderFailure.forbidden }
    guard (200..<300).contains(status) else { throw ReaderFailure.network }
    if template == "error" || (try !doc.select(".blockMessage--error").isEmpty()) {
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
                                pinned: try !row.select(".structItem-status--sticky").isEmpty()))
    }
    var forums: [ForumEntry] = []
    for node in try doc.select(".node") {
      let anchor = try node.select(".node-title a").first()
      guard let link = SitePolicy.resolve(try anchor?.attr("href"), from: url, internalOnly: true), seen.insert(link.absoluteString).inserted else { continue }
      forums.append(ForumEntry(title: text(anchor), url: link, subtitle: text(try node.select(".node-description").first())))
    }
    let kind: PageKind
    if !posts.isEmpty || template == "thread_view" { kind = .posts }
    else if !threads.isEmpty || ["forum_view", "watched_threads_list", "search_forum_view"].contains(template) { kind = .threads }
    else if !forums.isEmpty || template == "forum_list" { kind = .forums }
    else { throw ReaderFailure.unsupported }
    if kind == .posts && posts.isEmpty { throw ReaderFailure.unsupported }
    if kind == .threads && !rows.isEmpty() && threads.isEmpty { throw ReaderFailure.unsupported }
    func paging(_ direction: String) throws -> URL? {
      let link = try doc.select(".pageNav-jump--\(direction),link[rel=\(direction)]").first()
      return SitePolicy.resolve(try link?.attr("href"), from: url, internalOnly: true)
    }
    return ForumPage(url: url, title: title.isEmpty ? "Forums" : title, kind: kind, entries: forums + threads, posts: posts,
                     previous: try paging("prev"), next: try paging("next"),
                     pageNumber: Int(text(try doc.select(".pageNav-page--current").first())) ?? 1,
                     loggedIn: try doc.select("html").first()?.attr("data-logged-in") == "true")
  }
  private func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
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
        let poster = SitePolicy.resolve(try node.attr("poster"), from: page) ?? SitePolicy.resolve(try node.attr("data-poster"), from: page)
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
    try? doc.select(".advertisement,.ad-container,.adContainer,.adsbygoogle,[data-ad-slot]").remove()
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
