import SwiftUI

struct BookhouseReaderView: View {
  let initialURL: URL
  let navigate: (URL) -> Void
  let home: () -> Void
  @EnvironmentObject private var session: ForumSession
  @EnvironmentObject private var library: LibraryStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @StateObject private var posters = PosterStore()
  @State private var page: ForumPage?
  @State private var loading = false
  @State private var error: String?
  @State private var repliesLoaded = false
  @State private var repliesLoading = false
  @State private var repliesError: String?
  @State private var external: URL?
  @State private var image: ImageViewerPresentation?
  @State private var visibleID: String?
  @State private var restoreID: String?
  @State private var quickActions = false
  @State private var operation: Task<Void, Never>?
  @State private var requestID = UUID()
  private var current: URL { page?.url ?? initialURL }
  private var blocks: [BodyBlock] { page?.posts.first?.blocks ?? [] }

  var body: some View {
    ScrollViewReader { readingScroll($0) }
      .navigationTitle(AppText.text(page?.kind == .posts ? "Reading" : "Forbidden Library"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { readerToolbar }
      .background { ExternalBrowserPresenter(url: $external) }
      .sheet(item: $image) { ImageViewerSheet(source: $0.source).environmentObject(session) }
      .task { if page == nil { await load(initialURL) } }
      .onDisappear { savePosition(); operation?.cancel(); quickActions = false }
  }

  private var readingContent: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          Color.clear.frame(height: 1).id("top")
          if let page {
            Text(page.title).forumFont(.title2, weight: .bold).padding(.top, 8)
            if page.kind == .posts { novel(page) }
            else { catalog(page) }
          }
          if let error { errorPanel(error) }
          if loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24) }
          Color.clear.frame(height: 1).id("bottom")
        }.scrollTargetLayout().padding(.horizontal, 18).padding(.bottom, 28)
          .frame(maxWidth: 780).frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: page?.kind == .posts ? .systemBackground : .systemGroupedBackground))
  }

  private func errorPanel(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(message).foregroundStyle(.secondary)
      HStack {
        Button(AppText.text("Retry")) { startLoad(current, refresh: true) }.buttonStyle(.glass)
        Button(AppText.text("Site browser")) { external = current }.buttonStyle(.glass)
      }
    }.padding(.vertical, 20)
  }

  private var orderedIDs: [String] {
    let contentIDs: [String]
    if page?.kind == .posts { contentIDs = blocks.indices.map { "paragraph-\($0)" } + ["replies"] }
    else { contentIDs = page?.entries.map(\.id) ?? [] }
    return ["top"] + contentIDs + ["bottom"]
  }

  private func readingScroll(_ proxy: ScrollViewProxy) -> some View {
    readingContent
      .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.1) { ids in
        guard !loading else { return }
        if let first = orderedIDs.first(where: { ids.contains($0) }) { visibleID = first }
      }
      .onChange(of: restoreID) { _, value in
        guard let value else { return }
        DispatchQueue.main.async { proxy.scrollTo(value, anchor: .top); restoreID = nil }
      }
      .overlay(alignment: .bottomTrailing) {
        if quickActions {
          ReaderQuickActions(canJump: page != nil, busy: loading,
            top: { quickActions = false; proxy.scrollTo("top", anchor: .top) },
            bottom: { quickActions = false; proxy.scrollTo("bottom", anchor: .bottom) },
            refresh: { quickActions = false; startLoad(current, refresh: true) })
            .padding(.trailing, 14).padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
      }
  }

  @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button(AppText.text("Home"), systemImage: "house", action: home)
        Button(AppText.text("Bookmark"), systemImage: library.contains(current) ? "bookmark.fill" : "bookmark") {
          library.toggle(current, title: page?.title ?? current.path)
        }.disabled(page == nil)
        Button(AppText.text("Site browser"), systemImage: "safari") { external = current }
      }
      if BookhouseSitePolicy.route(current)?.kind == .search {
        ToolbarItemGroup(placement: .bottomBar) {
          Button(AppText.text("Previous page"), systemImage: "chevron.left") { if let target = page?.previous { startLoad(target) } }
            .disabled(loading || page?.previous == nil)
          Text(AppText.format("Page %@", String(page?.pageNumber ?? 1))).forumFont(.subheadline).monospacedDigit()
          Button(AppText.text("Next page"), systemImage: "chevron.right") { if let target = page?.next { startLoad(target) } }
            .disabled(loading || page?.next == nil)
        }
      }
      ToolbarSpacer(.flexible, placement: .bottomBar)
      ToolbarItem(placement: .bottomBar) {
        Button {
          withAnimation(reduceMotion ? nil : .spring(response: 0.3)) { quickActions.toggle() }
        } label: { Image(systemName: quickActions ? "xmark" : "ellipsis") }
          .accessibilityLabel(AppText.text("Page actions"))
      }
  }

  @ViewBuilder private func catalog(_ page: ForumPage) -> some View {
    if !page.tags.isEmpty { ForumTagStrip(tags: page.tags, navigate: open) }
    let featured = page.entries.filter(\.pinned)
    if !featured.isEmpty {
      DisclosureGroup(AppText.text("Featured novels")) {
        ForEach(featured) { entry in ForumEntryCard(entry: entry, isForum: false, navigate: open).id(entry.id) }
      }.forumFont(.subheadline).padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    ForEach(page.entries.filter { !$0.pinned }) { entry in
      ForumEntryCard(entry: entry, isForum: false, navigate: open).id(entry.id)
    }
    if page.entries.isEmpty { Text(AppText.text("No results")).foregroundStyle(.secondary) }
    if BookhouseSitePolicy.route(page.url)?.kind != .search, let next = page.next {
      Button { startLoad(next, append: true) } label: {
        HStack { Spacer(); Label(AppText.text("Load more novels"), systemImage: "chevron.down"); Spacer() }
      }.buttonStyle(.glass).disabled(loading).padding(.vertical, 8)
    }
  }

  @ViewBuilder private func novel(_ page: ForumPage) -> some View {
    if let post = page.posts.first {
      HStack(spacing: 12) {
        if !post.author.isEmpty { Label(post.author, systemImage: "person") }
        Text(post.date)
      }.forumFont(.caption).foregroundStyle(.secondary)
      Divider().padding(.bottom, 6)
      ForEach(Array(post.blocks.enumerated()), id: \.offset) { index, block in
        RichBodyView(blocks: [block], posters: posters, navigate: open,
                     play: { if let url = $0.url { external = url } },
                     openImage: { image = ImageViewerPresentation(source: $0) }, purchase: { _ in }, purchasing: false)
          .id("paragraph-\(index)")
      }
      Divider().padding(.top, 16)
      VStack(alignment: .leading, spacing: 12) {
        Text(AppText.text("Replies and continuations")).forumFont(.headline)
        if !repliesLoaded {
          Button(AppText.text("Show replies and continuations")) { operation = Task { await loadReplies() } }
            .buttonStyle(.glass).disabled(repliesLoading || loading)
          if repliesLoading { ProgressView() }
          if let repliesError { Text(repliesError).forumFont(.caption).foregroundStyle(.secondary) }
        } else if page.entries.isEmpty {
          Text(AppText.text("No replies yet")).forumFont(.subheadline).foregroundStyle(.secondary)
        }
      }.id("replies")
      ForEach(page.entries) { entry in ForumEntryCard(entry: entry, isForum: false, navigate: open).id(entry.id) }
    }
  }

  private func open(_ url: URL) {
    savePosition()
    if BookhouseSitePolicy.readable(url) { navigate(url) }
    else { external = url }
  }
  private func startLoad(_ url: URL, refresh: Bool = false, append: Bool = false) {
    operation?.cancel()
    operation = Task { await load(url, refresh: refresh, append: append) }
  }
  @MainActor private func load(_ url: URL, refresh: Bool = false, append: Bool = false) async {
    let token = UUID(); requestID = token
    loading = true; error = nil
    defer { if requestID == token { loading = false } }
    do {
      let snapshot = refresh ? nil : session.pages.value(for: url)
      let loaded: ForumPage
      if let snapshot { loaded = snapshot.page }
      else { loaded = try await session.load(url, cacheResult: true) }
      guard !Task.isCancelled, requestID == token else { return }
      if append, var existing = page {
        var seen = Set(existing.entries.map(\.id))
        existing.entries += loaded.entries.filter { seen.insert($0.id).inserted }
        existing.next = loaded.next
        page = existing
        session.pages.store(existing)
      } else {
        page = loaded
        repliesLoaded = !loaded.entries.isEmpty && loaded.kind == .posts
        repliesError = nil
        visibleID = snapshot?.visibleID ?? "top"
        restoreID = visibleID
        library.remember(loaded, session: session, checkMaximum: false)
      }
    } catch {
      guard !Task.isCancelled, requestID == token else { return }
      self.error = AppText.error(error)
    }
  }
  @MainActor private func loadReplies() async {
    guard !repliesLoading, let source = page?.url, let target = BookhouseSitePolicy.replies(source) else { return }
    repliesLoading = true; repliesError = nil
    defer { repliesLoading = false }
    do {
      let result = try await session.load(target)
      guard !Task.isCancelled, page?.url == source else { return }
      page?.entries = result.entries
      repliesLoaded = true
      if let page { session.pages.store(page) }
    } catch {
      if !Task.isCancelled { repliesError = AppText.error(error) }
    }
  }
  private func savePosition() {
    if let page { session.pages.savePosition(visibleID, for: page.url) }
  }
}
