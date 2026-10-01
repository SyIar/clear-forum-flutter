import ForumUI
import SwiftUI

struct BookhouseReaderView: View {
  let initialURL: URL
  let navigate: (URL) -> Void
  let home: () -> Void
  let search: () -> Void
  var followedBookID: String? = nil
  @EnvironmentObject private var session: ForumSession
  @EnvironmentObject private var library: LibraryStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
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
  @State private var bottomPanel: ReaderBottomPanel?
  @State private var selectingPage = false
  @State private var operation: Task<Void, Never>?
  @State private var requestID = UUID()
  @State private var selectingChapter = false
  @State private var chapterNotice: String?
  @State private var anchors: BookhouseChapterAnchors?
  @State private var restoring = false
  @State private var scrollPhase: ScrollPhase = .idle
  @State private var edgeArmed = false
  @State private var pendingChapter: Int?
  @State private var failedTarget: URL?
  @State private var latestVisibleIDs: [String] = []
  @State private var progressSave: Task<Void, Never>?
  private var current: URL { page?.url ?? initialURL }
  private var blocks: [BodyBlock] { page?.posts.first?.blocks ?? [] }
  private var book: BookhouseFollowedBook? { followedBookID.flatMap { library.document.followedBooks[$0] } }
  private var publication: BookhouseChapter? {
    book?.chapters.first { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(current) }
  }
  private var lastReadableChapter: Int { anchors?.byParagraph.values.max() ?? publication?.last ?? 0 }
  private var nextPublication: BookhouseChapter? {
    book?.chapter(containing: lastReadableChapter + 1, excluding: publication?.url)
  }

  var body: some View {
    ScrollViewReader { readingScroll($0) }
      .navigationTitle(AppText.text(page?.kind == .posts ? "Reading" : "Forbidden Library"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { readerToolbar }
      .forumSheet(isPresented: $selectingPage) {
        if let page { PageSelector(page: page) { if let target = page.url(forPage: $0) { startLoad(target) } } }
      }
      .forumSheet(isPresented: $selectingChapter) {
        if let book { BookhouseChapterPicker(book: book) { openChapter($0, number: $1) } }
      }
      .background { ExternalBrowserPresenter(url: $external) }
      .sheet(item: $image) { ImageViewerSheet(source: $0.source).environmentObject(session) }
      .task { if page == nil { await load(initialURL) } }
      .onDisappear { savePosition(); progressSave?.cancel(); operation?.cancel(); bottomPanel = nil }
      .onChange(of: scenePhase) { _, phase in if phase != .active { savePosition() } }
  }

  private var readingContent: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: page?.kind == .posts ? 8 : 16) {
          Color.clear.frame(height: 1).id("top")
          if let page {
            Text(page.title).forumFont(.title2, weight: .bold).padding(.top, 8)
            if page.kind == .posts { novel(page) }
            else { catalog(page) }
          }
          if let error { errorPanel(error) }
          if let chapterNotice { Text(chapterNotice).appFont(.caption).foregroundStyle(.secondary) }
          if loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24) }
          Color.clear.frame(height: 1).id("bottom")
        }.scrollTargetLayout().padding(.horizontal, 18).padding(.bottom, 28)
          .frame(maxWidth: 780).frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: page?.kind == .posts ? .systemBackground : .systemGroupedBackground))
    .environment(\.readerReferer, current)
  }

  private func errorPanel(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(message).foregroundStyle(.secondary)
      HStack {
        Button(AppText.text("Retry")) { startLoad(failedTarget ?? current, refresh: true) }.buttonStyle(.glass)
        Button(AppText.text("Site browser")) { external = failedTarget ?? current }.buttonStyle(.glass)
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
        latestVisibleIDs = ids
        guard !loading, !restoring else { return }
        observeVisiblePosition(ids)
      }
      .task(id: restoreID) {
        guard let value = restoreID else { return }
        await Task.yield()
        proxy.scrollTo(value, anchor: .top)
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        restoring = false; restoreID = nil
        observeVisiblePosition(latestVisibleIDs)
      }
      .onScrollPhaseChange { _, phase in
        scrollPhase = phase
        if phase == .tracking { setBottomPanel(nil); edgeArmed = true }
        if phase == .idle { savePosition() }
      }
      .scrollBounceBehavior(.always, axes: .vertical)
      .onScrollGeometryChange(for: Int.self) { ReaderEdgePull($0).bottom } action: { _, pull in
        guard book != nil, edgeArmed, scrollPhase == .interacting, pull > 36,
              !loading, !restoring, error == nil else { return }
        edgeArmed = false
        openNextPublication()
      }
      .overlay(alignment: .bottom) { bottomControls(proxy: proxy) }
  }

  @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
      ToolbarItem(placement: .topBarTrailing) {
        ForumToolbarGroup {
          Button(action: home) { ForumToolbarIcon("house") }
            .accessibilityLabel(AppText.text("Home"))
          Button(action: search) { ForumToolbarIcon("magnifyingglass") }
            .accessibilityLabel(AppText.text("Search forum"))
          Button {
            library.toggle(current, title: page?.title ?? current.path)
          } label: { ForumToolbarIcon(library.contains(current) ? "bookmark.fill" : "bookmark") }
            .accessibilityLabel(AppText.text("Bookmark")).disabled(page == nil)
          Button { external = current } label: { ForumToolbarIcon("safari") }
            .accessibilityLabel(AppText.text("Site browser"))
        }
      }.sharedBackgroundVisibility(.hidden)
      if book != nil {
        ToolbarItem(placement: .bottomBar) {
          Button { selectingChapter = true } label: { ForumToolbarIcon("page.jump") }
            .accessibilityLabel(AppText.text("Chapters"))
        }
      } else if BookhouseSitePolicy.route(current)?.kind == .search {
        ToolbarItem(placement: .bottomBar) {
          Button { setBottomPanel(bottomPanel == .pages ? nil : .pages) } label: {
            ForumToolbarIcon(bottomPanel == .pages ? "xmark" : "page.jump").contentTransition(.opacity)
          }.buttonStyle(.borderless).accessibilityLabel(AppText.text("Choose page"))
            .accessibilityValue(bottomPanel == .pages ? AppText.text("Expanded") : AppText.text("Collapsed"))
        }
      }
      ToolbarSpacer(.flexible, placement: .bottomBar)
      ToolbarItem(placement: .bottomBar) {
        Button { setBottomPanel(bottomPanel == .actions ? nil : .actions) } label: {
          ForumToolbarIcon(bottomPanel == .actions ? "xmark" : "slider.horizontal.3").contentTransition(.opacity)
        }.buttonStyle(.borderless).accessibilityLabel(AppText.text("Page actions"))
          .accessibilityValue(bottomPanel == .actions ? AppText.text("Expanded") : AppText.text("Collapsed"))
      }
  }

  @ViewBuilder private func bottomControls(proxy: ScrollViewProxy) -> some View {
    if let bottomPanel {
      Group {
        switch bottomPanel {
        case .pages:
          ReaderPagingActions(pageNumber: page?.pageNumber ?? BookhouseSitePolicy.pageNumber(current),
            canGoBack: page?.previous != nil && !loading,
            canGoForward: page?.next != nil && !loading,
            canSelect: page != nil && !loading,
            previous: { if let target = page?.previous { startLoad(target) } },
            select: { setBottomPanel(nil); selectingPage = true },
            next: { if let target = page?.next { startLoad(target) } })
        case .actions:
          ReaderQuickActions(canJump: page != nil, busy: loading,
            top: { setBottomPanel(nil); proxy.scrollTo("top", anchor: .top) },
            bottom: { setBottomPanel(nil); proxy.scrollTo("bottom", anchor: .bottom) },
            refresh: { startLoad(current, refresh: true) })
        }
      }
      .padding(.bottom, 12)
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
  }
  private func setBottomPanel(_ panel: ReaderBottomPanel?) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { bottomPanel = panel }
  }

  @ViewBuilder private func catalog(_ page: ForumPage) -> some View {
    if !page.tags.isEmpty { ForumTagStrip(tags: page.tags, navigate: open) }
    let featured = page.entries.filter(\.pinned)
    if !featured.isEmpty {
      DisclosureGroup(AppText.text("Featured novels")) {
        ForEach(featured) { entry in ForumEntryCard(entry: entry, isForum: false, navigate: open, formatBookhouseTitle: true).id(entry.id) }
      }.appFont(.subheadline).padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    ForEach(page.entries.filter { !$0.pinned }) { entry in
      ForumEntryCard(entry: entry, isForum: false, navigate: open, formatBookhouseTitle: true).id(entry.id)
        .modifier(BookhouseFollowMenu(entry: entry, enabled: BookhouseSitePolicy.route(page.url)?.kind == .search))
    }
    if page.entries.isEmpty { Text(AppText.text("No results")).foregroundStyle(.secondary) }
    if BookhouseSitePolicy.route(page.url)?.kind != .search, let next = page.next {
      Button { startLoad(next, append: true) } label: {
        HStack { Spacer(); Label(AppText.text("Load more novels"), forumSymbol: "chevron.down"); Spacer() }
      }.buttonStyle(.glass).disabled(loading).padding(.vertical, 8)
    }
  }

  @ViewBuilder private func novel(_ page: ForumPage) -> some View {
    if let post = page.posts.first {
      HStack(spacing: 12) {
        if !post.author.isEmpty { Label(post.author, forumSymbol: "person").forumFont(.caption) }
        Text(post.date)
      }.appFont(.caption).foregroundStyle(.secondary)
      Divider().padding(.bottom, 6)
      ForEach(Array(post.blocks.enumerated()), id: \.offset) { index, block in
        RichBodyView(blocks: [block], posters: posters, navigate: open,
                     play: { if let url = $0.url { external = url } },
                     openImage: { image = ImageViewerPresentation(source: $0) }, purchase: { _ in }, purchasing: false)
          .environment(\.readerBodyStyle, .novel)
          .id("paragraph-\(index)")
      }
      Divider().padding(.top, 16)
      if let book, let publication {
        HStack {
          Button(AppText.text("Previous chapter")) {
            if let previous = book.chapter(containing: publication.first - 1) { openChapter(previous, number: publication.first - 1) }
          }.disabled(loading || book.chapter(containing: publication.first - 1) == nil)
          Spacer()
          Button(AppText.text("Chapters")) { selectingChapter = true }
          Spacer()
          Button(AppText.text("Next chapter")) { openNextPublication() }
            .disabled(loading || nextPublication == nil)
        }.appFont(.subheadline).buttonStyle(.glass).padding(.vertical, 12)
        Text(nextPublication != nil ? AppText.text("Swipe up at the end to continue reading.") :
          lastReadableChapter < book.latestChapter ? AppText.text("The next chapter is missing. Choose a chapter from the catalog.") : AppText.text("You have reached the latest chapter."))
          .appFont(.caption).foregroundStyle(.secondary)
      } else {
      VStack(alignment: .leading, spacing: 12) {
        Text(AppText.text("Replies and continuations")).appFont(.headline)
        if !repliesLoaded {
          Button(AppText.text("Show replies and continuations")) { operation = Task { await loadReplies() } }
            .buttonStyle(.glass).disabled(repliesLoading || loading)
          if repliesLoading { ProgressView() }
          if let repliesError { Text(repliesError).appFont(.caption).foregroundStyle(.secondary) }
        } else if page.entries.isEmpty {
          Text(AppText.text("No replies yet")).appFont(.subheadline).foregroundStyle(.secondary)
        }
      }.id("replies")
      ForEach(page.entries) { entry in ForumEntryCard(entry: entry, isForum: false, navigate: open).id(entry.id) }
      }
    }
  }

  private func open(_ url: URL) {
    savePosition()
    if BookhouseSitePolicy.readable(url) { navigate(url) }
    else { external = url }
  }
  private func startLoad(_ url: URL, refresh: Bool = false, append: Bool = false) {
    savePosition()
    progressSave?.cancel()
    setBottomPanel(nil)
    operation?.cancel()
    operation = Task { await load(url, refresh: refresh, append: append) }
  }
  @MainActor private func load(_ url: URL, refresh: Bool = false, append: Bool = false) async {
    let token = UUID(); requestID = token
    loading = true; error = nil; failedTarget = nil; edgeArmed = false
    defer { if requestID == token { loading = false } }
    do {
      let snapshot = refresh ? nil : session.pages.value(for: url)
      let loaded: ForumPage
      if let snapshot { loaded = snapshot.page }
      else { loaded = try await session.load(url, cacheResult: true) }
      guard !Task.isCancelled, requestID == token else { return }
      if let book, !book.accepts(loaded) { throw BookhouseFollowingFailure.author }
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
        chapterNotice = nil
        if let book, let publication = book.chapters.first(where: { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(loaded.url) }) {
          let parsed = BookhouseChapterAnchors(blocks: loaded.posts.first?.blocks ?? [], chapter: publication)
          anchors = parsed
          if let number = pendingChapter {
            if let paragraph = parsed.paragraph(for: number) { visibleID = "paragraph-\(paragraph)" }
            else {
              visibleID = "paragraph-0"
              if number != publication.first { chapterNotice = AppText.text("This post has no recognizable heading for the requested chapter. Showing the publication from its beginning.") }
            }
          } else if let position = book.position, position.url == publication.url, blocks.indices.contains(position.paragraph) {
            visibleID = "paragraph-\(position.paragraph)"
          } else { visibleID = "paragraph-0" }
          pendingChapter = nil
        }
        latestVisibleIDs = []; restoring = true
        restoreID = visibleID
        library.remember(loaded, session: session, checkMaximum: false)
      }
    } catch {
      guard !Task.isCancelled, requestID == token else { return }
      self.error = AppText.error(error)
      failedTarget = url
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
    guard let id = followedBookID, let publication, let visibleID,
          visibleID.hasPrefix("paragraph-"), let index = Int(visibleID.dropFirst(10)), blocks.indices.contains(index) else { return }
    let number = anchors?.chapter(at: index, fallback: publication.first) ?? publication.first
    library.recordBook(id, url: current, chapter: number, paragraph: index)
  }
  private func observeVisiblePosition(_ ids: [String]) {
    let candidates = book == nil ? orderedIDs : blocks.indices.map { "paragraph-\($0)" }
    if let first = candidates.first(where: { ids.contains($0) }) {
      if first == "bottom", book != nil { return }
      visibleID = first
      progressSave?.cancel()
      progressSave = Task {
        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        savePosition()
      }
    }
  }
  private func openChapter(_ chapter: BookhouseChapter, number: Int) {
    guard !loading else { return }
    pendingChapter = number
    startLoad(chapter.url)
  }
  private func openNextPublication() {
    guard let next = nextPublication else { return }
    openChapter(next, number: lastReadableChapter + 1)
  }
}
