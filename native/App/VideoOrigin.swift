import Foundation

struct VideoOrigin: Codable {
  let title: String
  let page: URL
  let thumbnail: URL?
}

@MainActor
enum VideoOrigins {
  private static var values: [URL: VideoOrigin] = [:]
  private static var order: [URL] = []
  static func register(_ source: URL, title: String, page: URL, thumbnail: URL? = nil) {
    values[source] = VideoOrigin(title: title, page: page, thumbnail: thumbnail)
    order.removeAll { $0 == source }; order.append(source)
    while order.count > 128 { values[order.removeFirst()] = nil }
  }
  static func get(_ source: URL) -> VideoOrigin? { values[source] }
}
