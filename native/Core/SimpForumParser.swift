import Foundation
import SwiftSoup

struct SimpForumParser {
  private let unwanted = "script,style,object,embed,input,textarea,select,svg,noscript,.adsbygoogle,.advertisement,.ad-container,.adContainer,.ad-block,.sponsor,[data-ad],[data-ad-slot],[hidden]"
  func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    let doc = try SwiftSoup.parse(source)
    if SimpSitePolicy.searchResults(url) { try SimpSearch.validate(doc, url: url, status: status) }
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
      guard let link = SimpSitePolicy.resolve(try anchor?.attr("href"), from: url, internalOnly: true), seen.insert(link.absoluteString).inserted else { continue }
      threads.append(ForumEntry(title: text(anchor), url: link,
                                subtitle: text(try row.select(".structItem-minor .username").first()),
                                pinned: try !row.select(".structItem-status--sticky").isEmpty(), thumbnail: thumbnail(row, page: url),
                                tags: try tags(row.select(".structItem-title").first(), page: url)))
    }
    if template == "search_results" {
      let results = try doc.select(".block-row .contentRow")
      for row in results {
        let heading = try row.select(".contentRow-title").first()
        let anchor = try heading?.select("a[href]").first { !$0.hasClass("labelLink") }
        guard let link = SimpSitePolicy.resolve(try anchor?.attr("href"), from: url, internalOnly: true),
              SimpSitePolicy.threadKey(link) != nil || link.path.hasPrefix("/posts/"),
              seen.insert(link.absoluteString).inserted else { continue }
        let resultTags = try tags(heading, page: url)
        try heading?.select(".label,.label-append").remove()
        guard !text(anchor).isEmpty else { continue }
        threads.append(ForumEntry(title: text(anchor), url: link,
                                  subtitle: text(try row.select(".contentRow-minor").first()),
                                  thumbnail: thumbnail(row, page: url), tags: resultTags,
                                  excerpt: text(try row.select(".contentRow-snippet").first())))
      }
      if threads.isEmpty, !results.isEmpty() { throw ReaderFailure.unsupported }
      if threads.isEmpty, try doc.select(".blockMessage").isEmpty() { throw ReaderFailure.unsupported }
    }
    var forums: [ForumEntry] = []
    for node in try doc.select(".node") {
      let anchor = try node.select(".node-title a").first()
      guard let link = SimpSitePolicy.resolve(try anchor?.attr("href"), from: url, internalOnly: true), seen.insert(link.absoluteString).inserted else { continue }
      let category = node.parents().first { $0.hasClass("block--category") }
      let sectionAnchor = try category?.select(".u-anchorTarget[id]").first()?.id()
      forums.append(ForumEntry(title: text(anchor), url: link, subtitle: text(try node.select(".node-description").first()), sectionAnchor: sectionAnchor))
    }
    let kind: PageKind
    if !posts.isEmpty || template == "thread_view" { kind = .posts }
    else if !threads.isEmpty || ["forum_view", "watched_threads_list", "search_forum_view", "search_results"].contains(template) { kind = .threads }
    else if !forums.isEmpty || template == "forum_list" { kind = .forums }
    else { throw ReaderFailure.unsupported }
    if kind == .posts && posts.isEmpty { throw ReaderFailure.unsupported }
    if kind == .threads && !rows.isEmpty() && threads.isEmpty { throw ReaderFailure.unsupported }
    func paging(_ direction: String) throws -> URL? {
      let link = try doc.select(".pageNav-jump--\(direction),.pageNavSimple-el--\(direction),link[rel=\(direction)]").first()
      return SimpSitePolicy.resolve(try link?.attr("href"), from: url, internalOnly: true)
    }
    let next = try paging("next")
    let pageNumber = Int(text(try doc.select(".pageNav-page--current").first())) ?? SimpSitePolicy.pageNumber(url)
    let pageRoot = SimpSitePolicy.pageRoot(url)
    let pageLinks = try doc.select(".pageNav-page a[href],.pageNavSimple-el--last,link[rel=last]").array()
      .compactMap { SimpSitePolicy.resolve(try? $0.attr("href"), from: url, internalOnly: true) }
      .filter { SimpSitePolicy.pageRoot($0) == pageRoot }
    let lastPage = (pageLinks + [next].compactMap { $0 }).max { SimpSitePolicy.pageNumber($0) < SimpSitePolicy.pageNumber($1) }
    let totalPages = try doc.select(".pageNavSimple-el--current[data-last],.js-pageJump[data-last]").array()
      .compactMap { Int((try? $0.attr("data-last")) ?? "") }.filter { (1...99_999).contains($0) }.max()
    let hasLaterPage = next != nil || lastPage.map { SimpSitePolicy.pageNumber($0) > pageNumber } == true || (totalPages ?? 1) > pageNumber
    let maximum = kind == .posts && !hasLaterPage ? posts.compactMap { Int($0.number.dropFirst().replacingOccurrences(of: ",", with: "")) }.max() : nil
    var breadcrumbs: [ForumEntry] = []
    if let trail = try doc.select(".p-breadcrumbs").first() {
      for link in try trail.select("a[href]") {
        guard let target = SimpSitePolicy.resolve(try link.attr("href"), from: url, internalOnly: true), !text(link).isEmpty else { continue }
        breadcrumbs.append(ForumEntry(title: text(link), url: target))
      }
    }
    return ForumPage(url: url, title: title.isEmpty ? AppText.text("Forums") : title, kind: kind, entries: forums + threads, posts: posts,
                     previous: try paging("prev"), next: next, pageNumber: pageNumber,
                     loggedIn: try doc.select("html").first()?.attr("data-logged-in") == "true",
                     lastPage: lastPage, maximumPostNumber: maximum, breadcrumbs: breadcrumbs, tags: headingTags, totalPages: totalPages,
                     thumbnail: kind == .posts ? threadThumbnail(doc, page: url) : nil)
  }
  private func threadThumbnail(_ doc: Document, page: URL) -> URL? {
    let logos = ((try? doc.select(".p-header-logo img,.p-nav-smallLogo img").array()) ?? [])
      .compactMap { thumbnailURL(try? $0.attr("src"), page: page) }
    for selector in ["meta[property=og:image]", "meta[name=twitter:image]", "link[rel=image_src]"] {
      guard let node = try? doc.select(selector).first(),
            let url = thumbnailURL(try? node.attr(node.tagName() == "link" ? "href" : "content"), page: page),
            !logos.contains(url), !url.path.lowercased().contains("/logo_default/") else { continue }
      return url
    }
    return nil
  }
  private func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
  private func tags(_ node: Element?, page: URL) throws -> [ForumTag] {
    guard let node else { return [] }
    var seen = Set<String>()
    return try node.select(".labelLink[href]").array().compactMap { link in
      let title = text(link)
      guard !title.isEmpty, let url = SimpSitePolicy.resolve(try link.attr("href"), from: page, internalOnly: true),
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
      return SimpSitePolicy.resolve(parts.url?.absoluteString, from: page)
    }
    return SimpSitePolicy.resolve(candidate.absoluteString, from: page)
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
        if let url = SimpSitePolicy.linkDestination(try anchor?.attr("href"), from: page) {
          blocks.append(BodyBlock(kind: .link, label: text(anchor).isEmpty ? url.host ?? AppText.text("Link") : text(anchor), url: url))
        }
        return
      }
      if tag == "img" {
        let alt = try node.attr("alt")
        if node.hasClass("smilie") { runs.append(TextRun(text: alt)); return }
        flush()
        let lazy = try node.attr("data-src")
        if let url = SimpSitePolicy.resolve(lazy.isEmpty ? try node.attr("src") : lazy, from: page) {
          blocks.append(BodyBlock(kind: .image, label: alt.isEmpty ? AppText.text("Image") : alt, url: url,
                                  original: OriginalImageSource.resolve(node, page: page, preview: url, link: href), aspectRatio: ratio(node)))
        }
        return
      }
      if ["iframe", "video", "audio"].contains(tag) {
        flush()
        var candidates = [try node.attr("src"), try node.attr("data-src")]
        if tag != "iframe" { candidates.append(try node.select("source[src]").first()?.attr("src") ?? "") }
        let url = SimpSitePolicy.resolve(candidates.first { !$0.isEmpty }, from: page)
        let poster = try SimpSitePolicy.resolve(node.attr("poster"), from: page) ?? SimpSitePolicy.resolve(node.attr("data-poster"), from: page)
        blocks.append(BodyBlock(kind: .media, label: url?.host ?? AppText.text("Embedded media"), url: url, poster: poster, aspectRatio: ratio(node), direct: tag != "iframe"))
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
        blocks.append(BodyBlock(kind: .spoiler, children: children, label: AppText.text("Spoiler")))
        return
      }
      if tag == "pre" { flush(); blocks.append(BodyBlock(kind: .code, label: text(node))); return }
      if tag == "br" { runs.append(TextRun(text: "\n")); return }
      let boundary = ["p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4", "table", "tr"].contains(tag)
      if boundary { flush() }
      if tag == "li" { runs.append(TextRun(text: "\u{2022} ")) }
      let link = tag == "a" ? SimpSitePolicy.linkDestination(try node.attr("href"), from: page) : href
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
    return candidates.compactMap { SimpSitePolicy.resolve($0, from: page) }.first {
      ($0.port == nil || $0.port == 443) && $0.absoluteString.utf8.count <= 8192
    }
  }
}
