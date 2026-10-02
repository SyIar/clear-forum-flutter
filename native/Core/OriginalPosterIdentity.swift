import Foundation

extension LibraryDocument {
  func isOriginalPoster(_ post: ForumPost, in page: ForumPage) -> Bool {
    guard site == .south, site.accepts(page.url), page.kind == .posts,
          let author = post.authorID, SouthSitePolicy.validAuthorID(author) else { return false }
    // Later pages and cached pages can reuse an owner observed on the first
    // floor, in a verified GF header action, or in the thread's directory row.
    let owner = page.originalPosterID ?? page.posts.first(where: { $0.number == "#0" })?.authorID ??
      SouthSitePolicy.threadKey(page.url).flatMap { presentations[$0]?.authorID }
    return author == owner
  }
}
