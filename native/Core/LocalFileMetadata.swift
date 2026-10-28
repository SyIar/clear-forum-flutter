import Foundation
import Darwin

/// File attributes travel with renames and stay outside the visible folder listing.
enum LocalFileMetadata {
  private static let arrivalKey = "dev.sylar.forumlite.arrival"
  static let conversionKey = "dev.sylar.forumlite.png-source"

  static func read(_ key: String, at file: URL) -> Data? {
    let count = getxattr(file.path, key, nil, 0, 0, XATTR_NOFOLLOW)
    guard count > 0, count <= 4096 else { return nil }
    var bytes = Data(count: count)
    let actual = bytes.withUnsafeMutableBytes { getxattr(file.path, key, $0.baseAddress, count, 0, XATTR_NOFOLLOW) }
    return actual == count ? bytes : nil
  }
  static func write(_ data: Data, key: String, at file: URL) throws {
    let result = data.withUnsafeBytes { setxattr(file.path, key, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
    guard result == 0 else { throw CocoaError(.fileWriteUnknown) }
  }
  static func arrival(at file: URL) -> Date? {
    if let data = read(arrivalKey, at: file), let text = String(data: data, encoding: .utf8),
       let time = Double(text), time.isFinite { return Date(timeIntervalSince1970: time) }
    // Historical files do not have an ingestion ledger. Birth time is the closest
    // available evidence; modification time can be the publisher's original date.
    return try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
  }
  static func arrived(_ file: URL, at date: Date = Date()) throws {
    try write(Data(String(date.timeIntervalSince1970).utf8), key: arrivalKey, at: file)
  }
}
