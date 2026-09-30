import Foundation

enum PostTextExport {
  static func text(in blocks: [BodyBlock]) -> String {
    blocks.map { block in
      switch block.kind {
      case .paragraph:
        return block.runs.map(\.text).joined()
      case .code:
        return block.label
      case .quote, .spoiler:
        return [block.label, text(in: block.children)].filter { !$0.isEmpty }.joined(separator: "\n")
      case .link, .media:
        let address = block.url?.absoluteString ?? ""
        return [block.label, address == block.label ? "" : address].filter { !$0.isEmpty }.joined(separator: "\n")
      case .image:
        // Copy readable text, not image transport URLs or preview metadata.
        return ""
      case .purchase:
        // Purchase actions can contain verification tokens; never export them.
        return ""
      }
    }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
  }
}
