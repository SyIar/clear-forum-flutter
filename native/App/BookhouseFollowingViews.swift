import ForumUI
import SwiftUI

private enum BookhouseChapterText {
  static func status(_ number: Int, latest: Bool) -> String {
    let key: String
    if BookhouseChapterTitle.isExtra(number) { key = latest ? "Latest extra %@" : "Reading extra %@" }
    else { key = latest ? "Latest chapter %@" : "Reading chapter %@" }
    return AppText.format(key, String(BookhouseChapterTitle.localNumber(number)))
  }
}

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
                  Text(book.position.map { BookhouseChapterText.status($0.chapter, latest: false) } ?? AppText.text("Not started"))
                    .foregroundStyle(.secondary)
                  Text(BookhouseChapterText.status(book.latestChapter, latest: true))
                    .foregroundStyle(book.updated ? .blue : .secondary)
                }.appFont(.caption).lineLimit(1).minimumScaleFactor(0.85)
              }.frame(maxWidth: .infinity, alignment: .leading)
              LibraryRefreshIndicator(phase: library.bookRefreshPhases[book.id], showsChevron: true)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
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
      Text(AppText.text("My followed books"))
    }
    .task(id: scenePhase) {
      if scenePhase == .active { await library.refreshBooks(session: session) }
    }
  }
}

struct BookhouseChapterPicker: View {
  let book: BookhouseFollowedBook
  let currentChapter: Int
  let session: ForumSession
  let select: (BookhouseChapter, Int) -> Void
  @ObservedObject var library: LibraryStore
  let selectCached: (BookhouseOfflineMatch) -> Void
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  @State private var selectedChapter = 1
  @State private var error: String?
  @ObservedObject private var offline = BookhouseOfflineStore.shared
  private var totalChapters: Int { max(1, book.sliderChapterCount) }
  private var selectionLabel: String {
    let number = book.chapterNumber(at: selectedChapter)
    if BookhouseChapterTitle.isExtra(number) {
      return AppText.format("Extra %@ of %@", String(BookhouseChapterTitle.localNumber(number)), String(book.latestExtraChapter))
    }
    return AppText.format("Chapter %@ of %@", String(number), String(book.latestRegularChapter))
  }
  private var progress: Binding<Double> {
    Binding(get: { Double(selectedChapter) / Double(totalChapters) }, set: {
      selectedChapter = min(totalChapters, max(1, Int(($0 * Double(totalChapters)).rounded())))
      error = nil
    })
  }
  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: 12) {
            HStack {
              Text(selectionLabel)
              Spacer()
              Text(Double(selectedChapter) / Double(totalChapters), format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.secondary)
            }.appFont(.subheadline).monospacedDigit()
            Slider(value: progress, in: 0...1, step: 1 / Double(totalChapters)) { editing in
              if !editing { jump() }
            }.disabled(book.chapters.isEmpty || totalChapters <= 1)
              .accessibilityLabel(AppText.text("Jump to chapter"))
              .accessibilityValue(selectionLabel)
          }.padding(.vertical, 6)
          if let error { Text(error).appFont(.caption).foregroundStyle(.secondary) }
          if offline.failedBooks.contains(book.id), let message = offline.error {
            Text(message).appFont(.caption).foregroundStyle(.secondary)
          }
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
            Button { offline.downloadAll(book, session: session) } label: {
              HStack(spacing: 6) {
                if offline.caching(book.id), let plan = offline.plan(for: book.id) {
                  ProgressView().controlSize(.mini)
                  Text(AppText.format("Caching %@/%@", String(plan.completed), String(plan.targets.count)))
                } else { Text(AppText.text("Cache all chapters")) }
              }.appFont(.caption).monospacedDigit()
            }.buttonStyle(.borderless).disabled(offline.caching(book.id) || book.chapters.isEmpty)
          }
        }
    }.onAppear { selectedChapter = min(totalChapters, max(1, book.sliderPosition(for: currentChapter))) }
  }
  private func jump() {
    let number = book.chapterNumber(at: selectedChapter)
    guard let chapter = book.chapter(containing: number) else {
      error = AppText.text("This chapter is not in the current catalog. Check for updates or choose another chapter.")
      return
    }
    finish(chapter, number)
  }
  private func finish(_ chapter: BookhouseChapter, _ number: Int) { dismiss(); select(chapter, number) }
  private func dismiss() { if forumDismiss.available { forumDismiss() } else { nativeDismiss() } }
}
