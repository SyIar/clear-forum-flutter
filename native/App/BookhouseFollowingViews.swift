import ForumUI
import SwiftUI

struct BookhouseFollowMenu: ViewModifier {
  let entry: ForumEntry
  var enabled = true
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
  func body(content: Content) -> some View {
    if enabled && session.site == .bookhouse {
      content.contextMenu {
        if let book = library.document.followedBook(for: entry) {
          Button(role: .destructive) { library.unfollowBook(book.id) } label: {
            Label(AppText.text("Stop following book"), forumSymbol: "bookmark.slash")
          }
        } else {
          Button { library.followBook(entry, session: session) } label: {
            Label(AppText.text("Follow book"), forumSymbol: "bookmark")
          }.disabled(BookhouseFollowedBook(entry: entry) == nil)
        }
      }.sensoryFeedback(.success, trigger: library.document.followedBook(for: entry)?.id)
    } else { content }
  }
}

struct BookhouseFollowingSection: View {
  @ObservedObject var library: LibraryStore
  @ObservedObject var session: ForumSession
  let open: (String) -> Void
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    Section {
      if library.document.readingBooks.isEmpty {
        Text(AppText.text("Long-press a numbered search result to follow a book."))
          .appFont(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(library.document.readingBooks) { book in
        VStack(alignment: .leading, spacing: 8) {
          Button { open(book.id) } label: {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(book.title).forumFont(.headline).foregroundStyle(.primary).lineLimit(2)
                  if book.updated {
                    Text(AppText.text("Updated")).appFont(.caption2).foregroundStyle(.blue)
                      .padding(.horizontal, 6).padding(.vertical, 3).background(.blue.opacity(0.1), in: Capsule())
                  }
                }
                Text(book.author).forumFont(.caption).foregroundStyle(.secondary)
                Text(book.position.map { AppText.format("Reading chapter %@", String($0.chapter)) } ?? AppText.text("Not started"))
                  .appFont(.caption).foregroundStyle(.secondary)
                Text(AppText.format("Latest chapter %@", String(book.latestChapter)))
                  .appFont(.caption).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity, alignment: .leading)
              LibraryRefreshIndicator(phase: library.bookRefreshPhases[book.id], showsChevron: true)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
          if let error = library.bookErrors[book.id] {
            HStack(alignment: .top) {
              Text(error).appFont(.caption).foregroundStyle(.secondary)
              Button(AppText.text("Retry")) { Task { await library.refreshBook(book.id, session: session) } }
                .buttonStyle(.borderless).disabled(library.bookRefreshPhases[book.id] == .checking)
            }
          }
        }.padding(.vertical, 4).modifier(ForumRefreshFeedback(phase: library.bookRefreshPhases[book.id]))
          .swipeActions { Button(AppText.text("Stop following book"), role: .destructive) { library.unfollowBook(book.id) } }
      }
    } header: {
      HStack {
        Text(AppText.text("My followed books"))
        Spacer()
        Button { Task { await library.refreshBooks(session: session, force: true) } } label: {
          Image(forumSymbol: "arrow.clockwise", size: 17).frame(width: 32, height: 32)
        }.buttonStyle(.borderless).disabled(library.document.readingBooks.isEmpty || library.bookRefreshPhases.values.contains(.checking))
          .accessibilityLabel(AppText.text("Check new chapters"))
      }
    }
    .task(id: scenePhase) {
      if scenePhase == .active { await library.refreshBooks(session: session) }
    }
  }
}

struct BookhouseChapterPicker: View {
  let book: BookhouseFollowedBook
  let select: (BookhouseChapter, Int) -> Void
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  @State private var number = ""
  @State private var error: String?
  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField(AppText.text("Chapter number"), text: $number).keyboardType(.numberPad)
            Button(AppText.text("Go")) { jump() }.buttonStyle(.borderless)
          }
          if let error { Text(error).appFont(.caption).foregroundStyle(.secondary) }
        }
        Section {
          ForEach(book.chapters) { chapter in
            Button { finish(chapter, chapter.first) } label: {
              HStack {
                Text(chapter.title).forumFont(.body).foregroundStyle(.primary)
                Spacer()
                if book.position?.url == chapter.url { Image(forumSymbol: "checkmark", size: 16) }
              }
            }.buttonStyle(.plain)
          }
        }
      }.navigationTitle(AppText.text("Chapters")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: { ForumToolbarIcon("xmark") }.accessibilityLabel(AppText.text("Close"))
          }
        }
    }
  }
  private func jump() {
    guard let value = BookhouseChapterTitle.number(number.trimmingCharacters(in: .whitespaces)),
          let chapter = book.chapter(containing: value) else {
      error = AppText.text("This chapter is not in the current catalog. Check for updates or choose another chapter.")
      return
    }
    finish(chapter, value)
  }
  private func finish(_ chapter: BookhouseChapter, _ number: Int) { dismiss(); select(chapter, number) }
  private func dismiss() { if forumDismiss.available { forumDismiss() } else { nativeDismiss() } }
}
