import Foundation
import SwiftSoup

struct SouthBodyParser {
  private func text(_ node: Element?) -> String { (try? node?.text()) ?? "" }
  private func ratio(_ node: Element) -> Double? {
    guard let w = Double((try? node.attr("width")) ?? ""), let h = Double((try? node.attr("height")) ?? ""),
          w > 0, h > 0, (w / h).isFinite else { return nil }
    return w / h
  }
  func parseBody(_ root: Element, page: URL) throws -> [BodyBlock] {
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
      for child in node.getChildNodes() {
        try walk(child, bold: bold || ["b", "strong", "h1", "h2", "h3", "h4"].contains(tag), italic: italic || ["i", "em"].contains(tag), href: link,
                 detectLinks: detectLinks && tag != "code")
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
    return candidates.compactMap { SouthSitePolicy.resolve($0, from: page) }.first {
      ($0.port == nil || $0.port == 443) && $0.absoluteString.utf8.count <= 8192
    }
  }
}
