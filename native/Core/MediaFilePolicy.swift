import Foundation

enum MediaFilePolicy {
  static let videoLimit: Int64 = 4 * 1024 * 1024 * 1024
  static let imageLimit: Int64 = 100 * 1024 * 1024
  static func isHLS(_ url: URL, mime: String?) -> Bool {
    url.pathExtension.lowercased() == "m3u8" ||
      ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl"].contains(mime?.lowercased() ?? "")
  }
  static func responseError(status: Int, mime: String?, url: URL, bytes: Int64, limit: Int64,
                            resumed: Bool = false, contentRange: String? = nil, expectedBytes: Int64? = nil) -> String? {
    let completeResume = status == 206 && resumed && completeRange(contentRange, bytes: bytes)
    guard status == 200 || completeResume else {
      return status == 206 ? "The server returned only part of the file. Refresh the video and try again." :
        "Download failed with HTTP \(status). Refresh the source and try again."
    }
    if isHLS(url, mime: mime) { return "This is an HLS stream. Saving it to Photos is not supported yet." }
    if ["text/html", "application/xhtml+xml", "application/json"].contains(mime?.lowercased() ?? "") {
      return "The server returned a page instead of a media file."
    }
    if bytes == 0 { return "The server returned an empty file." }
    if bytes > limit { return "The file exceeds the download size limit." }
    if let expectedBytes, expectedBytes > 0, bytes != expectedBytes { return "The downloaded file is incomplete. Try resuming it again." }
    return nil
  }
  static func completeRange(_ value: String?, bytes: Int64) -> Bool {
    guard let value, value.range(of: #"^bytes [0-9]+-[0-9]+/[0-9]+$"#, options: .regularExpression) != nil else { return false }
    let numbers = value.dropFirst(6).split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap { Int64($0) }
    guard numbers.count == 3 else { return false }
    let (start, end, total) = (numbers[0], numbers[1], numbers[2])
    return start >= 0 && end >= start && total > 0 && end == total - 1 && bytes == total
  }
}
