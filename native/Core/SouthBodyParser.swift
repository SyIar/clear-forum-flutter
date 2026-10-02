import Foundation
import SwiftSoup

struct SouthBodyParser {
  private func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
  private func attachmentBlocks(_ node: Element, page: URL) throws -> [BodyBlock]? {
    guard node.id().range(of: #"^att_[0-9]+$"#, options: .regularExpression) != nil,
          node.parents().contains(where: { $0.hasClass("tpc_content") }) else { return nil }
    let identifier = String(node.id().dropFirst(4))
    let anchors = try node.select("a[href]").array()
    guard anchors.count == 1, let anchor = anchors.first, anchor.id() == "fg_" + identifier,
          let url = SouthSitePolicy.resolve(try anchor.attr("href"), from: page), SouthSitePolicy.sameOrigin(url),
          let attachment = SouthAttachment(url: url), attachment.attachmentID == identifier,
          !text(anchor).isEmpty, !node.hasAttr("hidden") else { return nil }
    // The tiny zip.gif is a file-type decoration, not a post image. Keep the
    // original filename and URL as one link, with the website's size/count below.
    func metadata(_ child: Node) -> String {
      if child === anchor { return "" }
      if let value = child as? TextNode { return value.getWholeText() }
      guard let element = child as? Element,
            !["img", "script", "style", "input", "noscript"].contains(element.tagName()), !element.hasAttr("hidden") else { return "" }
      return element.getChildNodes().map(metadata).joined(separator: " ")
    }
    let details = metadata(node)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .replacingOccurrences(of: #"^\s*\u9644\u4ef6\s*[:\uFF1A]\s*"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    var blocks = [BodyBlock(kind: .link, label: text(anchor), url: url)]
    if !details.isEmpty { blocks.append(BodyBlock(kind: .paragraph, runs: [TextRun(text: details)])) }
    return blocks
  }
  private func contentChildren(_ node: Element, page: URL) -> [Node] {
    let children = node.getChildNodes()
    // Only omit PHPWind's generated prefix on an uploaded-image attachment.
    // Identical words in an author's body, caption, or quote remain readable.
    guard node.id().range(of: #"^att_[0-9]+$"#, options: .regularExpression) != nil,
          node.parents().contains(where: { $0.hasClass("tpc_content") }),
          !node.parents().contains(where: { $0.id().hasPrefix("read_") }) else { return children }
    var index = 0
    while index < children.count, let text = children[index] as? TextNode,
          text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { index += 1 }
    guard index < children.count, let label = children[index] as? TextNode,
          ["\u{56fe}\u{7247}\u{ff1a}", "\u{56fe}\u{7247}:"].contains(label.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines)) else { return children }
    index += 1
    var hasBreak = false
    while index < children.count {
      if let text = children[index] as? TextNode, text.getWholeText().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { index += 1 }
      else if let element = children[index] as? Element, element.tagName() == "br" { hasBreak = true; index += 1 }
      else { break }
    }
    guard hasBreak, index < children.count, let image = children[index] as? Element, image.tagName() == "img",
          let source = SouthSitePolicy.resolve(try? image.attr("src"), from: page),
          SouthSitePolicy.sameOrigin(source), source.path.hasPrefix("/attachment/") else { return children }
    return Array(children.dropFirst(index))
  }
  private func ratio(_ node: Element) -> Double? {
    guard let w = Double((try? node.attr("width")) ?? ""), let h = Double((try? node.attr("height")) ?? ""),
          w > 0, h > 0, (w / h).isFinite else { return nil }
    return w / h
  }
  func parseBody(_ root: Element, page: URL) throws -> [BodyBlock] {
    if let attachment = try attachmentBlocks(root, page: page) { return attachment }
    var blocks: [BodyBlock] = []
    var runs: [TextRun] = []
    var literalRuns = Set<Int>()
    func flush() {
      if runs.contains(where: { $0.emoticon != nil || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        blocks.append(BodyBlock(kind: .paragraph, runs: SouthTextLinks.detect(in: runs, excluding: literalRuns)))
      }
      runs = []
      literalRuns = []
    }
    func walk(_ node: Node, bold: Bool = false, italic: Bool = false, href: URL? = nil, detectLinks: Bool = true) throws {
      if let node = node as? TextNode {
        if !detectLinks { literalRuns.insert(runs.count) }
        runs.append(TextRun(text: node.getWholeText().replacingOccurrences(of: #"[\t\r\n ]+"#, with: " ", options: .regularExpression), bold: bold, italic: italic, url: href))
        return
      }
      guard let node = node as? Element else { return }
      let tag = node.tagName()
      if let attachment = try attachmentBlocks(node, page: page) {
        flush(); blocks += attachment; return
      }
      if let purchase = SouthPurchase.offer(node, page: page) {
        flush()
        blocks.append(BodyBlock(kind: .purchase, purchase: purchase))
        return
      }
      if ["script", "style", "object", "embed", "form", "input", "textarea", "select", "svg", "noscript"].contains(tag) ||
          node.hasAttr("hidden") || node.hasAttr("data-ad") || node.hasAttr("data-ad-slot") ||
          ["advertisement", "ad-container", "adContainer", "ad-block", "adsbygoogle", "sponsor"].contains(where: node.hasClass) { return }
      if node.hasClass("bbCodeBlock--unfurl") {
        flush()
        let anchor = try node.select(".js-unfurl-title a").first()
        if let url = SouthSitePolicy.resolve(try anchor?.attr("href"), from: page) {
          blocks.append(BodyBlock(kind: .link, label: text(anchor).isEmpty ? url.host ?? AppText.text("Link") : text(anchor), url: url))
        }
        return
      }
      if tag == "img" {
        let alt = try node.attr("alt")
        let lazy = try node.attr("data-src")
        let source = SouthSitePolicy.resolve(lazy.isEmpty ? try node.attr("src") : lazy, from: page)
        if let source, SouthSitePolicy.isEmoticon(source) {
          runs.append(TextRun(text: alt.isEmpty ? AppText.text("Emoticon") : alt, bold: bold, italic: italic, url: href, emoticon: source))
          return
        }
        if node.hasClass("smilie") { runs.append(TextRun(text: alt)); return }
        flush()
        if let url = source {
          blocks.append(BodyBlock(kind: .image, label: alt.isEmpty ? AppText.text("Image") : alt, url: url,
                                  original: OriginalImageSource.resolve(node, page: page, preview: url, link: href), aspectRatio: ratio(node)))
        }
        return
      }
      if ["iframe", "video", "audio"].contains(tag) {
        flush()
        var candidates = [try node.attr("src"), try node.attr("data-src")]
        if tag != "iframe" { candidates.append(try node.select("source[src]").first()?.attr("src") ?? "") }
        let url = SouthSitePolicy.resolve(candidates.first { !$0.isEmpty }, from: page)
        let poster = try SouthSitePolicy.resolve(node.attr("poster"), from: page) ?? SouthSitePolicy.resolve(node.attr("data-poster"), from: page)
        blocks.append(BodyBlock(kind: .media, label: url?.host ?? AppText.text("Embedded media"), url: url, poster: poster, aspectRatio: ratio(node), direct: tag != "iframe"))
        return
      }
      if tag == "blockquote" || node.hasClass("bbCodeBlock--quote") || node.hasClass("blockquote") {
        flush()
        let content = try node.select(".bbCodeBlock-expandContent,.bbCodeBlock-content").first() ?? node
        blocks.append(BodyBlock(kind: .quote, children: try parseBody(content, page: page), label: text(try node.select(".bbCodeBlock-title").first())))
        return
      }
      if node.hasClass("bbCodeSpoiler") || node.hasClass("bbCodeInlineSpoiler") {
        flush()
        let children: [BodyBlock]
        if node.hasClass("bbCodeInlineSpoiler") { children = try parseBody(node, page: page) }
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
      let link: URL?
      if tag == "a" {
        let address = try node.attr("href")
        link = SouthSitePolicy.resolve(address, from: page) ?? SouthTextLinks.destination(address, from: page)
      } else { link = href }
      for child in contentChildren(node, page: page) {
        try walk(child, bold: bold || ["b", "strong", "h1", "h2", "h3", "h4"].contains(tag), italic: italic || ["i", "em"].contains(tag), href: link,
                 detectLinks: detectLinks && tag != "code")
      }
      if boundary { flush() }
    }
    for child in contentChildren(root, page: page) { try walk(child) }
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
    return candidates.compactMap { SouthSitePolicy.resolve($0, from: page) }.first {
      ($0.port == nil || $0.port == 443) && $0.absoluteString.utf8.count <= 8192
    }
  }
}
