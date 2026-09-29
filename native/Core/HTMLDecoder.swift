import Foundation
import CoreFoundation

enum HTMLDecoder {
  static func decode(_ data: Data, encodingName: String?) throws -> String {
    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      guard let value = String(data: data.dropFirst(3), encoding: .utf8) else { throw ReaderFailure.encoding }
      return value
    }
    if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
      // Foundation may silently discard an incomplete trailing UTF-16 code unit.
      guard data.count.isMultiple(of: 2), let value = String(data: data, encoding: .utf16) else { throw ReaderFailure.encoding }
      return value
    }
    let head = String(decoding: data.prefix(8192), as: UTF8.self)
    let pattern = #"(?i)<meta\b[^>]*\bcharset\s*=\s*["']?\s*([a-zA-Z0-9_-]+)"#
    var declared: String?
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
       let range = Range(match.range(at: 1), in: head) { declared = String(head[range]) }
    for name in [encodingName, declared].compactMap({ $0 }) {
      let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
      // The superset also handles pages declaring GB2312 while serving GBK bytes.
      let iana = ["gb2312", "gbk", "x-gbk"].contains(normalized) ? "gb18030" : normalized
      let encoding = CFStringConvertIANACharSetNameToEncoding(iana as CFString)
      guard encoding != kCFStringEncodingInvalidId else { continue }
      let ns = CFStringConvertEncodingToNSStringEncoding(encoding)
      if let result = String(data: data, encoding: String.Encoding(rawValue: ns)) { return result }
    }
    if let result = String(data: data, encoding: .utf8) { return result }
    throw ReaderFailure.encoding
  }
}
