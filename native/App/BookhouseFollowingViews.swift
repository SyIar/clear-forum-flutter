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
  @ObservedObject private var offline = BookhouseOfflineStore.shared
  var body: some View {
    Section {
      if library.document.readingBooks.isEmpty {
        Text(AppText.text("Long-press a numbered search result to follow a book."))
          .appFont(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(library.document.readingBooks.filter { !library.onlyUpdates || $0.updated }) { book in
        VStack(alignment: .leading, spacing: 8) {
          Button { open(book.id) } label: {
            HStack(spacing: 10) {
              VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                  Text(book.title).forumFont(.headline).foregroundStyle(.primary).lineLimit(1).layoutPriority(1)
                  Text(book.author).forumFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 12) {
                  Text(book.position.map { AppText.format("Reading chapter %@", String($0.chapter)) } ?? AppText.text("Not started"))
                    .foregroundStyle(.secondary)
                  Text(AppText.format("Latest chapter %@", String(book.latestChapter)))
                    .foregroundStyle(book.updated ? .blue : .secondary)
                }.appFont(.caption).lineLimit(1).minimumScaleFactor(0.85)
              }.frame(maxWidth: .infinity, alignment: .leading)
              LibraryRefreshIndicator(phase: library.bookRefreshPhases[book.id], showsChevron: true)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
          if let error = library.bookErrors[book.id] {
            Text(error).appFont(.caption).foregroundStyle(.secondary)
          }
        }.modifier(ForumRefreshFeedback(phase: library.bookRefreshPhases[book.id]))
          .contextMenu {
            Button(AppText.text("Cache next five chapters"), forumSymbol: "arrow.down.to.line") { offline.download(book, session: session) }.disabled(offline.busy)
          }
          .swipeActions { Button(AppText.text("Stop following book"), role: .destructive) { library.unfollowBook(book.id) } }
        if offline.activeBook == book.id {
          HStack {
            ProgressView(value: Double(offline.completed), total: Double(max(1, offline.total)))
            Button(AppText.text("Cancel")) { offline.cancel() }
          }.accessibilityLabel(AppText.text("Caching chapters"))
        }
      }
      if let error = offline.error { Text(error).appFont(.caption).foregroundStyle(.secondary) }
    } header: {
      HStack {
        Text(AppText.text("My followed books"))
        Spacer()
        Button { Task { await library.refreshBooks(session: session, manual: true) } } label: {
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
  @ObservedObject var library: LibraryStore
  let selectCached: (BookhouseOfflineMatch) -> Void
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  @State private var number = ""
  @State private var error: String?
  @ObservedObject private var offline = BookhouseOfflineStore.shared
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
                if offline.contains(chapter.url, bookID: book.id) {
                  Image(forumSymbol: "arrow.down.circle", size: 16).foregroundStyle(.secondary).accessibilityLabel(AppText.text("Available offline"))
                }
                if book.position?.url == chapter.url { Image(forumSymbol: "checkmark", size: 16) }
              }
            }.buttonStyle(.plain)
          }
        }
      }.navigationTitle(AppText.text("Chapters")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
              BookhouseOfflineSearchView(library: library) { match in dismiss(); selectCached(match) }
            } label: { ForumToolbarIcon("magnifyingglass") }
              .accessibilityLabel(AppText.text("Search cached text"))
          }
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
