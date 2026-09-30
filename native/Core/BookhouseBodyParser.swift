import Foundation
import SwiftSoup

struct BookhouseBodyParser {
  func parse(_ root: Element, page: URL) throws -> [BodyBlock] {
    var blocks: [BodyBlock] = []
    var runs: [TextRun] = []
    func flush() {
      if runs.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        blocks.append(BodyBlock(kind: .paragraph, runs: SouthTextLinks.detect(in: runs)))
      }
      runs = []
    }
    func walk(_ node: Node, bold: Bool = false, italic: Bool = false, href: URL? = nil) throws {
      if let text = node as? TextNode {
        let lines = text.getWholeText().replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        for (offset, line) in lines.enumerated() {
          if offset > 0 { flush() }
          // Bound a single SwiftUI text layout for very long unbroken passages.
          var remaining = line[...]
          while !remaining.isEmpty {
            let part = remaining.prefix(1600)
            runs.append(TextRun(text: String(part), bold: bold, italic: italic, url: href))
            remaining = remaining.dropFirst(part.count)
            if !remaining.isEmpty { flush() }
          }
        }
        return
      }
      guard let element = node as? Element else { return }
      let tag = element.tagName()
      if ["script", "style", "form", "button", "input", "textarea", "iframe", "object", "embed", "noscript"].contains(tag) ||
          element.hasAttr("hidden") || element.hasAttr("adv-id") ||
          ["adv-6park", "ad-container", "view_ad_incontent", "ai-detection-feedback", "view-gift", "vote-section"].contains(where: element.hasClass) { return }
      if tag == "br" { flush(); return }
      if tag == "img" {
        flush()
        let raw = try element.attr("data-src").isEmpty ? element.attr("src") : element.attr("data-src")
        if let target = BookhouseSitePolicy.resolve(raw, from: page) {
          blocks.append(BodyBlock(kind: .image, label: try element.attr("alt"), url: target, original: target))
        }
        return
      }
      let boundary = ["p", "div", "pre", "section", "li", "blockquote", "h1", "h2", "h3"].contains(tag)
      if boundary { flush() }
      let link = tag == "a" ? BookhouseSitePolicy.resolve(try element.attr("href"), from: page) : href
      for child in element.getChildNodes() {
        try walk(child, bold: bold || ["b", "strong", "h1", "h2", "h3"].contains(tag), italic: italic || ["i", "em"].contains(tag), href: link)
      }
      if boundary { flush() }
    }
    try walk(root)
    flush()
    return blocks
  }
}
