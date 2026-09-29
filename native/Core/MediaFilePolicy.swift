import Foundation

enum MediaFilePolicy {
  static let videoLimit: Int64 = 4 * 1024 * 1024 * 1024
  static let imageLimit: Int64 = 100 * 1024 * 1024
  static func isHLS(_ url: URL, mime: String?) -> Bool {
    url.pathExtension.lowercased() == "m3u8" ||
      ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl"].contains(mime?.lowercased() ?? "")
  }
  static func responseError(status: Int, mime: String?, url: URL, bytes: Int64, limit: Int64) -> String? {
    guard status == 200 else {
      return status == 206 ? "The server returned only part of the file. Refresh the video and try again." :
        "Download failed with HTTP \(status). Refresh the source and try again."
    }
    if isHLS(url, mime: mime) { return "This is an HLS stream. Saving it to Photos is not supported yet." }
    if ["text/html", "application/xhtml+xml", "application/json"].contains(mime?.lowercased() ?? "") {
      return "The server returned a page instead of a media file."
    }
    if bytes == 0 { return "The server returned an empty file." }
    if bytes > limit { return "The file exceeds the download size limit." }
    return nil
  }
}
