import ForumUI
import SwiftUI

struct SouthFollowingSection: View {
  @ObservedObject var library: LibraryStore
  @ObservedObject var session: ForumSession
  let open: (URL) -> Void

  var body: some View {
    Section {
      if library.document.following.isEmpty {
        Text(AppText.text("No followed authors")).appFont(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(library.document.following.filter { author in !library.onlyUpdates || author.topics.contains { library.document.isUnreadSouthThread($0.url) } }) { author in
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 10) {
            Button { openTopics(author) } label: {
              HStack(spacing: 10) {
                PostAvatar(url: author.avatar, author: author.name)
                Text(author.name).forumFont(.subheadline, weight: .semibold).foregroundStyle(.primary).lineLimit(1)
                Image(forumSymbol: "chevron.right", size: 11).font(.caption2).foregroundStyle(.tertiary)
              }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(AppText.format("All topics by %@", String(describing: author.name)))
            Spacer(minLength: 0)
            LibraryRefreshIndicator(phase: library.authorRefreshPhases[author.id])
            Button { library.unfollow(author.id) } label: { Image(forumSymbol: "person.badge.minus") }
              .buttonStyle(.borderless).accessibilityLabel(AppText.format("Unfollow %@", String(describing: author.name)))
          }
          ForEach(author.topics.filter { !library.onlyUpdates || library.document.isUnreadSouthThread($0.url) }) { topic in
            Divider()
            Button { open(topic.url) } label: {
              HStack(alignment: .top, spacing: 8) {
                Text(topic.title).forumFont(.subheadline).foregroundStyle(.primary).lineLimit(2)
                  .frame(maxWidth: .infinity, alignment: .leading)
                if library.document.isUnreadSouthThread(topic.url) {
                  Text(AppText.text("New")).appFont(.caption2, weight: .semibold).foregroundStyle(.blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.blue.opacity(0.12), in: Capsule()).fixedSize()
                }
              }.frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
          if author.topics.isEmpty && !library.refreshingAuthors.contains(author.id) {
            Text(author.checkedAt == nil ? AppText.text("Not refreshed") : AppText.text("No topics"))
              .appFont(.caption).foregroundStyle(.secondary)
          }
        }.padding(.vertical, 6)
          .modifier(ForumRefreshFeedback(phase: library.authorRefreshPhases[author.id]))
      }
    } header: {
      HStack {
        Text(AppText.text("Following"))
        Spacer()
        InfoButton(title: AppText.text("Following"), message: AppText.text("Open the post menu and choose Follow author. Refresh to load their latest topics."))
      }
    }
  }
  private func openTopics(_ author: SouthFollowedAuthor) {
    if let url = SouthSitePolicy.authorTopics(author.id) { open(url) }
  }
}
