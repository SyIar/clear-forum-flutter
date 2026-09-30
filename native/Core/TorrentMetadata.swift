import Foundation
import CryptoKit

struct TorrentMetadata {
  let name: String
  let magnet: URL
  let isPrivate: Bool
  let v2Only: Bool
  static let limit = 8 * 1024 * 1024
  static func isTorrent(name: String, mime: String = "") -> Bool {
    (name as NSString).pathExtension.lowercased() == "torrent" || mime.lowercased() == "application/x-bittorrent"
  }
  static func parse(_ data: Data) throws -> TorrentMetadata {
    guard !data.isEmpty, data.count <= limit else { throw TorrentError.invalid }
    var scanner = Scanner(bytes: Array(data))
    let root = try scanner.value(depth: 0)
    guard scanner.index == data.count else { throw TorrentError.invalid }
    let fields = try scanner.fields(root)
    guard let info = fields["info"] else { throw TorrentError.invalid }
    let details = try scanner.fields(info)
    guard let nameRange = details["name.utf-8"] ?? details["name"],
          let name = try scanner.string(nameRange), !name.isEmpty, name.utf8.count <= 4096,
          let pieceLength = details["piece length"], try scanner.integer(pieceLength) > 0 else { throw TorrentError.invalid }
    let v2 = try details["meta version"].map { try scanner.integer($0) == 2 } ?? false
    let v1: Bool
    if let pieces = details["pieces"] {
      let bytes = try scanner.stringBytes(pieces)
      guard bytes.count % 20 == 0, (details["length"] != nil) != (details["files"] != nil) else { throw TorrentError.invalid }
      v1 = true
    } else { v1 = false }
    guard v1 || (v2 && details["file tree"] != nil) else { throw TorrentError.invalid }
    var items: [URLQueryItem] = []
    let rawInfo = data.subdata(in: info)
    if v1 { items.append(URLQueryItem(name: "xt", value: "urn:btih:" + Insecure.SHA1.hash(data: rawInfo).map { String(format: "%02x", $0) }.joined())) }
    if v2 { items.append(URLQueryItem(name: "xt", value: "urn:btmh:1220" + SHA256.hash(data: rawInfo).map { String(format: "%02x", $0) }.joined())) }
    items.append(URLQueryItem(name: "dn", value: name))
    var trackers: [String] = []
    if let announce = fields["announce"], let tracker = try scanner.string(announce) { trackers.append(tracker) }
    if let tiers = fields["announce-list"] { trackers += try scanner.strings(tiers, depth: 0) }
    var seen = Set<String>()
    for tracker in trackers where seen.count < 20 {
      guard tracker.utf8.count <= 2048, let url = URL(string: tracker),
            ["http", "https", "udp"].contains(url.scheme?.lowercased() ?? ""), url.host != nil,
            url.user == nil, url.password == nil, seen.insert(tracker).inserted else { continue }
      items.append(URLQueryItem(name: "tr", value: tracker))
    }
    var link = URLComponents(); link.scheme = "magnet"; link.queryItems = items
    guard let magnet = link.url else { throw TorrentError.invalid }
    let isPrivate = try details["private"].map { try scanner.integer($0) == 1 } ?? false
    return TorrentMetadata(name: name, magnet: magnet, isPrivate: isPrivate, v2Only: v2 && !v1)
  }
  // Parse bounded bencode locally. Hash the original info bytes, never a re-encoding.
  private struct Scanner {
    let bytes: [UInt8]
    var index = 0
    var nodes = 0
    mutating func stringBytes() throws -> Range<Int> {
      let start = index
      while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
      guard index > start, index - start <= 9, index < bytes.count, bytes[index] == 58,
            index - start == 1 || bytes[start] != 48,
            let count = Int(String(decoding: bytes[start..<index], as: UTF8.self)) else { throw TorrentError.invalid }
      index += 1
      guard count <= bytes.count - index else { throw TorrentError.invalid }
      let range = index..<(index + count); index += count; return range
    }
    mutating func value(depth: Int) throws -> Range<Int> {
      nodes += 1
      guard depth <= 64, nodes <= 100000, index < bytes.count else { throw TorrentError.invalid }
      let start = index
      switch bytes[index] {
      case 48...57: _ = try stringBytes()
      case 105:
        index += 1
        let integerStart = index
        while index < bytes.count, bytes[index] != 101 { index += 1 }
        guard index < bytes.count, index - integerStart <= 20 else { throw TorrentError.invalid }
        let text = String(decoding: bytes[integerStart..<index], as: UTF8.self)
        guard text.range(of: #"^(0|-?[1-9][0-9]*)$"#, options: .regularExpression) != nil, Int64(text) != nil else { throw TorrentError.invalid }
        index += 1
      case 108, 100:
        let dictionary = bytes[index] == 100; index += 1
        var previous: Range<Int>?
        while index < bytes.count, bytes[index] != 101 {
          if dictionary {
            let key = try stringBytes()
            if let previous { guard bytes[previous].lexicographicallyPrecedes(bytes[key]) else { throw TorrentError.invalid } }
            previous = key
          }
          _ = try value(depth: depth + 1)
        }
        guard index < bytes.count else { throw TorrentError.invalid }
        index += 1
      default: throw TorrentError.invalid
      }
      return start..<index
    }
    mutating func fields(_ range: Range<Int>) throws -> [String: Range<Int>] {
      guard bytes[range.lowerBound] == 100 else { throw TorrentError.invalid }
      index = range.lowerBound + 1; nodes = 0
      var fields: [String: Range<Int>] = [:]
      while index < range.upperBound - 1 {
        let key = try stringBytes()
        let name = String(decoding: bytes[key], as: UTF8.self)
        fields[name] = try value(depth: 0)
      }
      return fields
    }
    mutating func stringBytes(_ range: Range<Int>) throws -> Range<Int> { index = range.lowerBound; return try stringBytes() }
    mutating func string(_ range: Range<Int>) throws -> String? {
      let payload = try stringBytes(range)
      return String(bytes: bytes[payload], encoding: .utf8)
    }
    func integer(_ range: Range<Int>) throws -> Int64 {
      guard bytes[range.lowerBound] == 105,
            let value = Int64(String(decoding: bytes[(range.lowerBound + 1)..<(range.upperBound - 1)], as: UTF8.self)) else { throw TorrentError.invalid }
      return value
    }
    mutating func strings(_ range: Range<Int>, depth: Int) throws -> [String] {
      guard depth < 4 else { return [] }
      if bytes[range.lowerBound] != 108 { return try string(range).map { [$0] } ?? [] }
      index = range.lowerBound + 1; var result: [String] = []
      while index < range.upperBound - 1, result.count < 20 {
        let child = try value(depth: depth + 1), next = index
        result += try strings(child, depth: depth + 1); index = next
      }
      return Array(result.prefix(20))
    }
  }
}

enum TorrentError: LocalizedError {
  case invalid
  var errorDescription: String? { AppText.text("This torrent is invalid, unsupported, or larger than the 8 MB metadata limit.") }
}
