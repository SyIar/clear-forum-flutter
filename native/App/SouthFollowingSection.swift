import SwiftUI

struct SouthFollowingSection: View {
  @ObservedObject var library: LibraryStore
  @ObservedObject var session: ForumSession
  let open: (URL) -> Void

  var body: some View {
    Section {
      if library.document.following.isEmpty {
        Text("No followed authors").font(.forum(.subheadline)).foregroundStyle(.secondary)
      }
      ForEach(library.document.following) { author in
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 10) {
            Button { openTopics(author) } label: {
              HStack(spacing: 10) {
                PostAvatar(url: author.avatar, author: author.name)
                Text(author.name).font(.forum(.subheadline, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
              }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("All topics by \(author.name)")
            Spacer(minLength: 0)
            if library.refreshingAuthors.contains(author.id) { ProgressView().controlSize(.small) }
            Button { library.unfollow(author.id) } label: { Image(systemName: "person.badge.minus") }
              .buttonStyle(.borderless).accessibilityLabel("Unfollow \(author.name)")
          }
          ForEach(author.topics) { topic in
            Divider()
            Button { open(topic.url) } label: {
              HStack(alignment: .top, spacing: 8) {
                Text(topic.title).font(.forum(.subheadline)).foregroundStyle(.primary).lineLimit(2)
                  .frame(maxWidth: .infinity, alignment: .leading)
                if library.document.isUnreadSouthThread(topic.url) {
                  Text("New").font(.forum(.caption2, weight: .semibold)).foregroundStyle(.blue)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.blue.opacity(0.12), in: Capsule()).fixedSize()
                }
              }.frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
          if let error = library.authorErrors[author.id] {
            HStack(alignment: .top) {
              Text(error).font(.forum(.caption)).foregroundStyle(.secondary)
              Spacer(minLength: 8)
              Button("Retry") { Task { await library.refreshAuthor(author.id, session: session) } }
                .font(.forum(.caption)).buttonStyle(.borderless).disabled(library.refreshingAuthors.contains(author.id))
            }
          } else if author.topics.isEmpty && !library.refreshingAuthors.contains(author.id) {
            Text(author.checkedAt == nil ? "Not refreshed" : "No topics")
              .font(.forum(.caption)).foregroundStyle(.secondary)
          }
        }.padding(.vertical, 6)
      }
    } header: {
      HStack {
        Text("Following")
        Spacer()
        InfoButton(title: "Following", message: "Tap an author's avatar and choose Follow author. Refresh to load their latest topics.")
      }
    }
  }
  private func openTopics(_ author: SouthFollowedAuthor) {
    if let url = SouthSitePolicy.authorTopics(author.id) { open(url) }
  }
}
