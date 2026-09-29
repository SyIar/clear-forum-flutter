import Foundation

struct ForumParser {
  func parse(_ source: String, url: URL, status: Int = 200) throws -> ForumPage {
    switch ForumSite(url: url) {
    case .simp: return try SimpForumParser().parse(source, url: url, status: status)
    case .south: return try SouthForumParser().parse(source, url: url, status: status)
    case nil: throw ReaderFailure.unsupported
    }
  }
  static func poster(_ source: String, page: URL) -> URL? { SimpForumParser.poster(source, page: page) }
}
