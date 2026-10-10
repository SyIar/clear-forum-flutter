import Foundation

enum PageKind: String, Codable { case forums, threads, posts }
enum ReaderFailure: String, Error, LocalizedError {
  case login, verification, forbidden, rateLimit, network, unsupported, storage, encoding
  var errorDescription: String? {
    switch self {
    case .login: return AppText.text("Sign in to read this page.")
    case .verification: return AppText.text("Complete the site's verification in Site browser, then choose Read page.")
    case .forbidden: return AppText.text("Your account cannot access this page.")
    case .rateLimit: return AppText.text("The site is receiving too many requests. Try again later.")
    case .network: return AppText.text("Could not load the page. Check your connection and try again.")
    case .unsupported: return AppText.text("This page cannot be displayed in the reader. Try Site browser.")
    case .encoding: return AppText.text("Could not decode this page. Open Site browser and choose Read page.")
    case .storage: return AppText.text("Could not read your saved library. Your existing data has been preserved.")
    }
  }
}
struct ForumEntry: Identifiable, Codable {
  var id: String { url.absoluteString }
  let title: String
  let url: URL
  var subtitle = ""
  var pinned = false
  var thumbnail: URL?
  var sectionAnchor: String?
  var tags: [ForumTag] = []
  var authorID: String?
  var authorName: String?
  var excerpt = ""
  var postedAt: String?
  // Includes the original post; absence means the page did not declare a count.
  var totalPostCount: Int?
}
struct ForumTag: Identifiable, Codable, Equatable {
  var id: String { url.absoluteString + ":" + title }
  let title: String
  let url: URL
}
struct TextRun: Equatable, Codable {
  var text: String
  var bold = false
  var italic = false
  var url: URL?
  var emoticon: URL?
}
enum BlockKind: String, Codable { case paragraph, quote, spoiler, code, image, link, media, purchase }
struct BodyBlock: Identifiable, Codable {
  var id = UUID()
  var kind: BlockKind
  var runs: [TextRun] = []
  var children: [BodyBlock] = []
  var label = ""
  var url: URL?
  var poster: URL?
  var original: URL?
  var aspectRatio: Double?
  var direct = false
  var purchase: SouthPurchaseOffer?
}
struct ForumPost: Identifiable, Codable {
  let id: String
  var author: String
  var date: String
  var number: String
  var blocks: [BodyBlock]
  var authorID: String?
  var avatar: URL?
  var avatarOriginal: URL?
  var authorFilterURL: URL?
}
struct ForumPage: Codable {
  var url: URL
  var title: String
  var kind: PageKind
  var entries: [ForumEntry]
  var posts: [ForumPost]
  var previous: URL?
  var next: URL?
  var pageNumber: Int
  var loggedIn: Bool?
  var lastPage: URL?
  var maximumPostNumber: Int?
  var breadcrumbs: [ForumEntry] = []
  var tags: [ForumTag] = []
  var totalPages: Int?
  var thumbnail: URL?
  var poll: SouthPoll?
  var originalPosterID: String?
  var pageCount: Int {
    min(99_999, [pageNumber, totalPages ?? 1, lastPage.map(SitePolicy.pageNumber) ?? 1, next.map(SitePolicy.pageNumber) ?? 1].max() ?? 1)
  }
  func url(forPage number: Int) -> URL? {
    guard (1...pageCount).contains(number) else { return nil }
    return SitePolicy.pageURL(url, number: number)
  }
}
