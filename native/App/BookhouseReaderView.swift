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
  @Environment(\.colorScheme) private var colorScheme
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
  @State private var readingWindow = BookhouseReadingWindow()
  @State private var scrollTracking = ReaderScrollTracking()
  @State private var edgeLoading: ReaderEdge?
  @State private var edgeFailure: ReaderEdgeFailure?
  @State private var edgeTask: Task<Void, Never>?
  @State private var edgeRequestID = UUID()
  @State private var pendingPage: ForumPage?
  @State private var lastJoinedEdge: ReaderEdge = .next
  @State private var restoring = false
  @State private var scrollPhase: ScrollPhase = .idle
  @State private var pendingChapter: Int?
  @State private var failedTarget: URL?
  @State private var latestVisibleIDs: [String] = []
  @State private var progressSave: Task<Void, Never>?
  @State private var chapterPrefetch = BookhouseChapterPrefetch()
  @State private var readerVisible = false
  @ObservedObject private var settings = ReadingSettings.shared
  @ObservedObject private var offline = BookhouseOfflineStore.shared
  @State private var showingSettings = false
  @State private var returnPoint: ReadingReturnPoint?
  @State private var pendingReturnAnchor: String?
  private var current: URL { page?.url ?? initialURL }
  private var blocks: [BodyBlock] { page?.posts.first?.blocks ?? [] }
  private var book: BookhouseFollowedBook? { followedBookID.flatMap { library.document.followedBooks[$0] } }
  @ScaledMetric(relativeTo: .body) private var paragraphSpacing: CGFloat = 14

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
      .forumSheet(isPresented: $showingSettings) { ReadingSettingsView() }
      .environment(\.readingAppearance, settings.value.normalized)
      .background { ExternalBrowserPresenter(url: $external) }
      .sheet(item: $image) { ImageViewerSheet(source: $0.source).environmentObject(session) }
      .task { if page == nil { await load(initialURL) } }
      .onAppear { readerVisible = true; prefetchNextChapter() }
      .onDisappear {
        readerVisible = false
        savePosition(); progressSave?.cancel(); operation?.cancel(); cancelAdjacent(); bottomPanel = nil
      }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active { savePosition(); chapterPrefetch.cancel() }
        else { prefetchNextChapter() }
      }
      .onChange(of: session.generation) { _, _ in chapterPrefetch.cancel() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
        chapterPrefetch.cancel()
      }
  }

  private var readingContent: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: page?.kind == .posts ? paragraphSpacing * settings.value.normalized.paragraphSpacing / 14 : 16) {
          Color.clear.frame(height: 1).id("top")
          if let page {
            Text(book?.title ?? page.title).forumFont(.title2, weight: .bold).padding(.top, 8)
            if page.kind == .posts, book != nil { continuousNovel }
            else if page.kind == .posts { novel(page) }
            else { catalog(page) }
          }
          if let error { errorPanel(error) }
          if let chapterNotice { Text(chapterNotice).appFont(.caption).foregroundStyle(.secondary) }
          if loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24) }
          Color.clear.frame(height: 1).id("bottom")
        }.scrollTargetLayout().padding(.horizontal, page?.kind == .posts ? settings.value.normalized.margin : 18).padding(.bottom, 28)
          .frame(maxWidth: 780).frame(maxWidth: .infinity)
    }
    .foregroundStyle(page?.kind == .posts ? settings.value.foreground : .primary)
    .background(page?.kind == .posts ? settings.value.background : Color(uiColor: .systemGroupedBackground))
    .environment(\.colorScheme, page?.kind == .posts && settings.value.theme != .system ? (settings.value.theme == .night ? .dark : .light) : colorScheme)
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
        trimWindow()
      }
      .onScrollPhaseChange { old, phase, context in
        let previousOffset = scrollTracking.pull.offset
        scrollTracking.record(ReaderEdgePull(context.geometry), interacting: old == .interacting || phase == .interacting)
        scrollPhase = phase
        if phase == .tracking || (phase == .interacting && old != .tracking) {
          scrollTracking.trigger.beginDrag(at: Double(phase == .tracking ? scrollTracking.pull.offset : previousOffset))
          setBottomPanel(nil)
        }
        if phase == .interacting || phase == .decelerating {
          checkEdgeDrag(phase: old == .interacting ? .interacting : phase)
        }
        if phase == .idle {
          checkEdgeDrag(phase: old)
          scrollTracking.trigger.endDrag()
          applyAdjacentPage(); trimWindow(); savePosition()
        } else if phase == .animating { scrollTracking.trigger.endDrag() }
      }
      .scrollBounceBehavior(.always, axes: .vertical)
      .onScrollGeometryChange(for: ReaderEdgePull.self) { ReaderEdgePull($0) } action: { _, pull in
        scrollTracking.record(pull, interacting: scrollPhase == .interacting)
        checkEdgeDrag()
      }
      .overlay(alignment: .top) {
        ReaderEdgeIndicator(edge: .previous, loading: edgeLoading == .previous, failure: edgeFailure) { loadAdjacent(.previous) }
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
            top: { rememberReturnPoint(); setBottomPanel(nil); proxy.scrollTo("top", anchor: .top) },
            bottom: { rememberReturnPoint(); setBottomPanel(nil); proxy.scrollTo("bottom", anchor: .bottom) },
            refresh: { startLoad(current, refresh: true) },
            settings: page?.kind == .posts ? { setBottomPanel(nil); showingSettings = true } : nil)
        }
      }
      .padding(.bottom, 12)
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    } else if let point = returnPoint {
      ReturnToReadingButton(restore: {
        startLoad(point.url, returnAnchor: point.anchor)
      }, dismiss: { returnPoint = nil; savePosition() }).disabled(loading || restoring)
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

  @ViewBuilder private var continuousNovel: some View {
    if let book {
      Text(book.author).forumFont(.caption).foregroundStyle(.secondary)
      Divider().padding(.bottom, 6)
      ForEach(readingWindow.paragraphs) { paragraph in
        RichBodyView(blocks: [paragraph.block], posters: posters, navigate: open,
          play: { if let url = $0.url { external = url } },
          openImage: { image = ImageViewerPresentation(source: $0) }, purchase: { _ in }, purchasing: false)
          .environment(\.readerBodyStyle, .novel)
          .environment(\.readerReferer, paragraph.url)
          .id(paragraph.id)
      }
      HStack {
        Spacer(minLength: 0)
        ReaderEdgeIndicator(edge: .next, loading: edgeLoading == .next, failure: edgeFailure) { loadAdjacent(.next) }
        Spacer(minLength: 0)
      }.frame(minHeight: edgeLoading == .next || edgeFailure?.edge == .next ? 44 : 0)
      if readingWindow.target(.next, book: book) == nil, let last = readingWindow.slices.last {
        Text(last.last < book.latestChapter ? AppText.text("The next chapter is missing. Choose a chapter from the catalog.") : AppText.text("You have reached the latest chapter."))
          .appFont(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
      }
    }
  }

  private func open(_ url: URL) {
    savePosition()
    if BookhouseSitePolicy.readable(url) { navigate(url) }
    else { external = url }
  }
  private func startLoad(_ url: URL, refresh: Bool = false, append: Bool = false, returnAnchor: String? = nil) {
    pendingReturnAnchor = returnAnchor
    savePosition()
    progressSave?.cancel()
    cancelAdjacent()
    setBottomPanel(nil)
    operation?.cancel()
    operation = Task { await load(url, refresh: refresh, append: append) }
  }
  @MainActor private func load(_ url: URL, refresh: Bool = false, append: Bool = false) async {
    let token = UUID(); requestID = token
    loading = true; error = nil; failedTarget = nil
    defer { if requestID == token { loading = false } }
    do {
      let snapshot = refresh ? nil : session.pages.value(for: url)
      let loaded: ForumPage
      if let snapshot { loaded = snapshot.page }
      else if !refresh, let book, let saved = offline.page(url, book: book) { loaded = saved; session.pages.store(saved) }
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
          guard readingWindow.reset(loaded, book: book) else { throw ReaderFailure.unsupported }
          var paragraph = 0
          if let number = pendingChapter {
            if let found = parsed.paragraph(for: number) { paragraph = found }
            else {
              if number != publication.first { chapterNotice = AppText.text("This post has no recognizable heading for the requested chapter. Showing the publication from its beginning.") }
            }
          } else if let position = book.position, position.url == publication.url, blocks.indices.contains(position.paragraph) {
            paragraph = position.paragraph
          }
          visibleID = BookhouseReadingParagraph.id(url: publication.url, index: paragraph)
          pendingChapter = nil
        }
        if let anchor = pendingReturnAnchor { visibleID = anchor; pendingReturnAnchor = nil; returnPoint = nil }
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
    guard returnPoint == nil else { return }
    if let page { session.pages.savePosition(visibleID, for: page.url) }
    guard let id = followedBookID, let paragraph = readingWindow.paragraph(id: visibleID) else { return }
    library.recordBook(id, url: paragraph.url, chapter: paragraph.chapter, paragraph: paragraph.index)
  }
  private func observeVisiblePosition(_ ids: [String]) {
    prefetchNextChapter()
    let candidates = book == nil ? orderedIDs : readingWindow.paragraphs.map(\.id)
    if let first = candidates.first(where: { ids.contains($0) }) {
      guard first != visibleID else { return }
      visibleID = first
      if let active = readingWindow.page(containing: first), active.url != page?.url {
        page = active
        library.remember(active, session: session, checkMaximum: false)
      }
      progressSave?.cancel()
      progressSave = Task {
        do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
        savePosition()
      }
    }
  }
  private func openChapter(_ chapter: BookhouseChapter, number: Int) {
    guard !loading else { return }
    rememberReturnPoint()
    pendingChapter = number
    startLoad(chapter.url)
  }
  private func rememberReturnPoint() {
    guard returnPoint == nil, let anchor = visibleID else { return }
    savePosition()
    returnPoint = ReadingReturnPoint(url: readingWindow.paragraph(id: anchor)?.url ?? current, anchor: anchor)
  }
  private func prefetchNextChapter() {
    guard readerVisible, scenePhase == .active, let book, !loading, !restoring, error == nil, edgeLoading == nil,
          let target = readingWindow.prefetchTarget(visibleIDs: latestVisibleIDs, book: book),
          session.pages.value(for: target.url) == nil else { return }
    chapterPrefetch.start(target.url) {
      let loaded: ForumPage
      if let saved = offline.page(target.url, book: book) { loaded = saved; session.pages.store(saved) }
      else { loaded = try await session.load(target.url, cacheResult: true) }
      guard book.accepts(loaded) else { throw BookhouseFollowingFailure.author }
      return loaded
    }
  }
  private func checkEdgeDrag(phase: ScrollPhase? = nil) {
    guard let book, !loading, !restoring, error == nil, edgeLoading == nil else { return }
    let pull = scrollTracking.pull, phase = phase ?? scrollPhase
    if let edge = scrollTracking.trigger.update(topPull: Double(pull.top), remaining: Double(pull.remaining), offset: Double(pull.offset),
      interacting: phase == .interacting, decelerating: phase == .decelerating,
      previous: readingWindow.target(.previous, book: book) != nil, next: readingWindow.target(.next, book: book) != nil) {
      loadAdjacent(edge)
    }
  }
  private func loadAdjacent(_ edge: ReaderEdge) {
    guard let book, !loading, edgeLoading == nil, let target = readingWindow.target(edge, book: book) else { return }
    edgeLoading = edge; edgeFailure = nil
    if edge == .previous { chapterPrefetch.cancel() }
    let token = UUID(); edgeRequestID = token
    edgeTask = Task { @MainActor in
      do {
        let loaded: ForumPage
        if let snapshot = session.pages.value(for: target.url) { loaded = snapshot.page }
        else if let saved = offline.page(target.url, book: book) { loaded = saved; session.pages.store(saved) }
        else if let prefetched = await chapterPrefetch.take(target.url) { loaded = prefetched }
        else {
          try Task.checkCancellation()
          loaded = try await session.load(target.url, cacheResult: true)
        }
        guard !Task.isCancelled, edgeRequestID == token else { return }
        pendingPage = loaded
        applyAdjacentPage()
      } catch {
        guard !Task.isCancelled, edgeRequestID == token else { return }
        edgeLoading = nil; edgeFailure = ReaderEdgeFailure(edge: edge, message: AppText.error(error))
      }
    }
  }
  private func applyAdjacentPage() {
    guard let book, let incoming = pendingPage, let edge = edgeLoading,
          edge == .next || scrollPhase == .idle else { return }
    var updated = readingWindow
    guard updated.insert(incoming, at: edge, book: book) else {
      pendingPage = nil; edgeLoading = nil
      edgeFailure = ReaderEdgeFailure(edge: edge, message: AppText.text("Could not join this chapter. Choose a chapter from the catalog."))
      return
    }
    let anchor = visibleID ?? readingWindow.paragraphs.first?.id
    var transaction = Transaction(); transaction.disablesAnimations = true
    withTransaction(transaction) {
      readingWindow = updated; pendingPage = nil; edgeLoading = nil; lastJoinedEdge = edge
      if edge == .previous { restoring = true; restoreID = anchor }
    }
    trimWindow()
  }
  private func trimWindow() {
    guard scrollPhase == .idle, !restoring else { return }
    var updated = readingWindow
    let first = updated.paragraphs.first?.id
    updated.trim(keeping: visibleID, preserving: lastJoinedEdge)
    guard updated.slices.count != readingWindow.slices.count else { return }
    var transaction = Transaction(); transaction.disablesAnimations = true
    withTransaction(transaction) {
      readingWindow = updated
      if first != updated.paragraphs.first?.id, let visibleID { restoring = true; restoreID = visibleID }
    }
  }
  private func cancelAdjacent() {
    chapterPrefetch.cancel()
    scrollTracking.trigger.endDrag()
    edgeRequestID = UUID(); edgeTask?.cancel(); edgeTask = nil
    edgeLoading = nil; pendingPage = nil; edgeFailure = nil
  }
}
