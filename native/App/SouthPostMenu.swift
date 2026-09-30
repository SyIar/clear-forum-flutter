import SwiftUI

struct SouthPostMenu: View {
  let post: ForumPost
  let busy: Bool
  let authorFilterActive: Bool
  let navigate: (URL) -> Void
  let openAvatar: () -> Void
  let selectText: () -> Void
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
  var body: some View {
    Menu {
      Button(AppText.text("Select text"), systemImage: "text.cursor") { selectText() }
      if let target = post.authorFilterURL {
        Button(AppText.text("Only this author"), systemImage: authorFilterActive ? "checkmark" : "person") { navigate(target) }
          .disabled(authorFilterActive)
      }
      Section {
        Button(AppText.text("View full-size avatar"), systemImage: "person.crop.square") { openAvatar() }
          .disabled(post.avatarOriginal == nil && post.avatar == nil)
        Button(AppText.text("View author threads"), systemImage: "text.bubble") {
          if let id = post.authorID, let target = SouthSitePolicy.authorTopics(id) { navigate(target) }
        }.disabled(post.authorID.flatMap(SouthSitePolicy.authorTopics) == nil)
        if let id = post.authorID, SouthSitePolicy.validAuthorID(id) {
          if library.document.followsAuthor(id) {
            Button(AppText.text("Unfollow author"), systemImage: "person.badge.minus") { library.unfollow(id) }
          } else {
            Button(AppText.text("Follow author"), systemImage: "person.badge.plus") { library.follow(post, session: session) }
          }
        }
      }
      Section {
        Button(AppText.text("Block author"), systemImage: "person.slash", role: .destructive) {
          if let id = post.authorID { library.change { $0.blockAuthor(id: id, name: post.author) } }
        }.disabled(post.authorID.map { !SouthSitePolicy.validAuthorID($0) } ?? true)
      }
    } label: {
      Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
        .frame(width: 24, height: 24)
        .glassEffect(.regular.tint(.blue.opacity(0.08)).interactive(), in: .circle)
        .frame(width: 44, height: 44).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(.blue).disabled(busy)
      .accessibilityLabel(AppText.format("Actions for %@", post.author))
  }
}
