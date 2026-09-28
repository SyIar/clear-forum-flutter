import Foundation

enum PageKind { case forums, threads, posts }
enum ReaderFailure: String, Error, LocalizedError {
  case login, verification, forbidden, rateLimit, network, unsupported, storage
  var errorDescription: String? {
    switch self {
    case .login: return "Sign in to read this page."
    case .verification: return "Complete the site's verification in Site browser, then choose Read page."
    case .forbidden: return "Your account cannot access this page."
    case .rateLimit: return "The site is receiving too many requests. Try again later."
    case .network: return "Could not load the page. Check your connection and try again."
    case .unsupported: return "This page cannot be displayed in the reader. Try Site browser."
    case .storage: return "Could not read your saved library. Your existing data has been preserved."
    }
  }
}
struct ForumEntry: Identifiable {
  var id: String { url.absoluteString }
  let title: String
  let url: URL
  var subtitle = ""
  var pinned = false
}
struct TextRun {
  var text: String
  var bold = false
  var italic = false
  var url: URL?
}
enum BlockKind { case paragraph, quote, spoiler, code, image, link, media }
struct BodyBlock: Identifiable {
  let id = UUID()
  var kind: BlockKind
  var runs: [TextRun] = []
  var children: [BodyBlock] = []
  var label = ""
  var url: URL?
  var poster: URL?
  var aspectRatio: Double?
  var direct = false
}
struct ForumPost: Identifiable {
  let id: String
  var author: String
  var date: String
  var number: String
  var blocks: [BodyBlock]
}
struct ForumPage {
  let url: URL
  var title: String
  var kind: PageKind
  var entries: [ForumEntry]
  var posts: [ForumPost]
  var previous: URL?
  var next: URL?
  var pageNumber: Int
  var loggedIn: Bool
  var lastPage: URL?
  var maximumPostNumber: Int?
}

extension SitePolicy {
  static let base = URL(string: "https://simpcity.cr/")!
  static func resolve(_ value: String?, from page: URL, internalOnly: Bool = false) -> URL? {
    guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
          let candidate = URL(string: raw, relativeTo: page)?.absoluteURL,
          candidate.scheme == "https", !(candidate.host ?? "").isEmpty,
          candidate.user == nil, candidate.password == nil else { return nil }
    var resolved = candidate
    if sameOrigin(candidate), candidate.path.range(of: #"^/threads/[^/]+\.\d+/unread/?$"#, options: .regularExpression) != nil,
       candidate.query == nil || candidate.query == "new=1" {
      var components = URLComponents(url: candidate, resolvingAgainstBaseURL: false)!
      components.path = candidate.path.replacingOccurrences(of: #"unread/?$"#, with: "", options: .regularExpression)
      components.query = nil
      resolved = components.url ?? candidate
    }
    return internalOnly && !readable(resolved) ? nil : resolved
  }
  static func withoutFragment(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    components.fragment = nil
    return components.url ?? url
  }
}
