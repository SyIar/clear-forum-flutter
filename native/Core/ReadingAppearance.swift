import Foundation

struct ReadingAppearance: Codable, Equatable {
  enum Theme: String, Codable, CaseIterable { case system, paper, night }
  var fontSize = 20.0
  var lineSpacing = 7.0
  var paragraphSpacing = 14.0
  var margin = 18.0
  var theme = Theme.system
  var normalized: Self {
    var value = self
    func clamp(_ number: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
      number.isFinite ? min(range.upperBound, max(range.lowerBound, number)) : fallback
    }
    value.fontSize = clamp(fontSize, 16...32, 20)
    value.lineSpacing = clamp(lineSpacing, 2...18, 7)
    value.paragraphSpacing = clamp(paragraphSpacing, 6...30, 14)
    value.margin = clamp(margin, 12...40, 18)
    return value
  }
}

// Explicit jumps preserve an independent return point; passive scrolling never replaces it.
struct ReadingReturnPoint: Equatable {
  let url: URL
  let anchor: String
}

enum DownloadQueuePolicy {
  static func safePath(_ components: [String]) -> Bool {
    !components.isEmpty && components.count <= 32 && components.allSatisfy {
      !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") && !$0.contains("\0")
    }
  }
  static func completedResponse(status: Int, contentRange: String?, bytes: Int64, resumed: Bool) -> Int {
    guard status == 206, resumed, bytes > 0, let contentRange,
          contentRange.hasPrefix("bytes ") else { return status }
    let parts = contentRange.dropFirst(6).split(separator: "/")
    guard parts.count == 2, let total = Int64(parts[1]), total == bytes else { return status }
    let range = parts[0].split(separator: "-")
    guard range.count == 2, let first = Int64(range[0]), let last = Int64(range[1]),
          first >= 0, first <= last, last == total - 1 else { return status }
    return 200
  }
}
