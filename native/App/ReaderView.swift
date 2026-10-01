import ForumUI
import SwiftUI
import WebKit

struct ReaderView: View {
  let initialURL: URL
  var home: () -> Void
  @ObservedObject var library: LibraryStore
  @ObservedObject var session: ForumSession
  @State private var url: URL?
  @State private var page: ForumPage?
  @State private var error: String?
  @State private var loading = false
  @State private var requestID = UUID()
  @State private var completedRequestID: UUID?
  @State private var forceNextLoad = false
  @State private var visibleID: String?
  @State private var pendingScrollAnchor: String?
  @State private var isVisible = false
  @State private var loadedGeneration = -1
  @State private var selectingPage = false
  @State private var presentation: ReaderPresentation?
  @State private var media: MediaViewerItem?
  @State private var imageSheet: ImageViewerPresentation?
  @State private var clearSession = false
  @State private var destination: ReaderDestination?
  @State private var external: URL?
  @State private var gofile: GofileDestination?
  @State private var hostedFiles: HostedFilesDestination?
  @State private var purchasing = false
  @State private var purchaseMessage: String?
  @State private var purchaseTask: Task<Void, Never>?
  @State private var textSelection: PostTextSelection?
  @State private var quickActionsExpanded = false
  @State private var showingDiagnostics = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var showingBlockedAuthors = false
  @State private var showingPinnedThreads = false
  @State private var selectedPinnedThread: URL?
  @State private var readingPages = ReaderPageWindow()
  @State private var scrollTracking = ReaderScrollTracking()
  @State private var lastEdgeEvent = "none"
  @State private var scrollPhase: ScrollPhase = .idle
  @State private var edgeLoading: ReaderEdge?
  @State private var edgeFailure: ReaderEdgeFailure?
  @State private var edgeTask: Task<Void, Never>?
  @State private var edgeRequestID = UUID()
  @State private var pendingPage: ForumPage?
  @StateObject private var posters = PosterStore()
  private var current: URL { SouthSitePolicy.canonicalThreadURL(url ?? initialURL) }
  private var displayPage: ForumPage? { page.map { readingPages.combined(active: $0) } }
  private var canRecordReading: Bool {
    session.site == .south && isVisible && scenePhase == .active && !loading && error == nil &&
      loadedGeneration == session.generation && completedRequestID == requestID && pendingScrollAnchor == nil &&
      destination == nil && media == nil && imageSheet == nil && external == nil && presentation == nil &&
      gofile == nil && hostedFiles == nil && textSelection == nil && !showingDiagnostics &&
      !selectingPage && !showingBlockedAuthors && !clearSession
  }
  private var pinnedThreads: [ForumEntry] {
    guard session.site == .south, let page = displayPage, page.kind == .threads else { return [] }
    return library.document.visibleContent(in: page).entries.filter(\.pinned)
  }
  init(initialURL: URL, library: LibraryStore, session: ForumSession, home: @escaping () -> Void) {
    self.initialURL = initialURL
    self.library = library
    self.session = session
    self.home = home
  }
  var body: some View {
    ScrollViewReader { proxy in
      presentedReader(proxy: proxy)
    }
    .environmentObject(library)
    .environmentObject(session)
  }
  private var scrollingReader: some View {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          Color.clear.frame(height: 1).id("top")
          if let error {
            ContentUnavailableView {
              Label(AppText.text("Could not load page"), forumSymbol: "wifi.exclamationmark")
            } description: { Text(error) } actions: {
              Button(AppText.text("Retry")) { reload() }.buttonStyle(.borderedProminent)
              Button(AppText.text("Site browser")) { openBrowser(current) }.buttonStyle(.bordered)
              Button(AppText.text("Page diagnostics"), forumSymbol: "ladybug") { showingDiagnostics = true }
            }
          } else if let page = displayPage {
            let visible = library.document.visibleContent(in: page)
            if !page.breadcrumbs.isEmpty {
              ScrollView(.horizontal) {
                HStack(spacing: 6) {
                  ForEach(Array(page.breadcrumbs.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { Image(forumSymbol: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary) }
                    Button(entry.title) { navigate(entry.url) }
                      .forumFont(.caption, weight: .medium).buttonStyle(.plain).foregroundStyle(.blue)
                      .padding(.horizontal, 6).frame(minHeight: 36)
                  }
                }
              }.scrollIndicators(.hidden).accessibilityLabel(AppText.text("Forum navigation"))
            }
            if !page.tags.isEmpty { ForumTagStrip(tags: page.tags, navigate: navigate) }
            Text(page.title).forumFont(.title2, weight: .bold).padding(.horizontal, 4)
            if page.kind == .posts {
              if let poll = visible.poll {
                SouthPollCard(poll: poll, busy: loading || purchasing) { openBrowser(page.url) }.id("poll")
              }
              ForEach(visible.posts) { post in
                PostCard(post: post, posters: posters, navigate: navigate, play: play, openImage: { imageSheet = ImageViewerPresentation(source: $0) }, purchase: buy,
                         purchasing: purchasing || loading,
                         authorFilterActive: post.authorFilterURL.map { SouthSitePolicy.authorID($0) == SouthSitePolicy.authorID(page.url) } ?? false,
                         openAvatar: session.site == .south ? { openAvatar(post) } : nil,
                         selectText: session.site == .south ? { textSelection = PostTextSelection(text: PostTextExport.text(in: post.blocks)) } : nil).id(post.id)
              }
              if visible.posts.isEmpty { ForumUnavailableView(AppText.text("No visible replies"), forumSymbol: "person.slash") }
            } else {
              directoryEntries(in: visible)
              if visible.entries.isEmpty { ForumUnavailableView(page.entries.isEmpty ? AppText.text("No threads yet") : AppText.text("No visible threads"), forumSymbol: "tray") }
            }
          } else { ProgressView(AppText.text("Loading page...")).frame(maxWidth: .infinity).padding(.top, 100) }
          if error == nil, page != nil, readingPages.target(.next) != nil {
            HStack {
              Spacer(minLength: 0)
              ReaderEdgeIndicator(edge: .next, loading: edgeLoading == .next, failure: edgeFailure) { loadAdjacent(.next) }
              Spacer(minLength: 0)
            }.frame(minHeight: 44).id("reader-next-page")
          }
        }.scrollTargetLayout().padding(.horizontal, 12).padding(.bottom, 14)
      }
      // Visibility is observation only. Binding the first visible row back to
      // scrollPosition kept re-pinning tall image posts as their layout changed.
      .defaultScrollAnchor(.top, for: .initialOffset)
      .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.01) { ids in
        guard !loading, error == nil, let page = displayPage else { return }
        let visible = library.document.visibleContent(in: page)
        let ordered = ["top", "poll"] + visible.posts.map(\.id) + visible.entries.map(\.id)
        if let first = ordered.first(where: { ids.contains($0) }) { visibleID = first }
        scrollTracking.visiblePostIDs = Set(ids).intersection(visible.posts.map(\.id))
        recordVisibleProgress()
      }
      .scrollBounceBehavior(.always, axes: .vertical)
      .onScrollGeometryChange(for: ReaderEdgePull.self) { ReaderEdgePull($0) } action: { _, pull in
        scrollTracking.record(pull, interacting: scrollPhase == .interacting)
        checkEdgeDrag()
      }
      .onScrollPhaseChange { old, phase, context in
        let previousOffset = scrollTracking.pull.offset
        scrollTracking.record(ReaderEdgePull(context.geometry), interacting: old == .interacting || phase == .interacting)
        scrollPhase = phase
        if phase == .tracking || (phase == .interacting && old != .tracking) {
          scrollTracking.trigger.beginDrag(at: Double(phase == .tracking ? scrollTracking.pull.offset : previousOffset))
          scrollTracking.peakTopPull = 0; scrollTracking.peakBottomPull = 0
        }
        if phase == .tracking { setQuickActions(false) }
        if phase == .interacting || phase == .decelerating {
          checkEdgeDrag(phase: old == .interacting ? .interacting : phase)
        }
        if phase == .idle {
          // The final geometry sample can arrive together with the idle phase.
          checkEdgeDrag(phase: old)
          scrollTracking.trigger.endDrag()
          applyAdjacentPage()
        } else if phase == .animating { scrollTracking.trigger.endDrag() }
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .environment(\.readerReferer, current)
      .navigationTitle(SouthSitePolicy.topicAuthorID(current) != nil ? AppText.text("Author threads") : page?.kind == .posts ? AppText.text("Thread") : AppText.text("Forums")).navigationBarTitleDisplayMode(.inline)
  }
  @ToolbarContentBuilder private var readerToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button(AppText.text("Home"), forumSymbol: "house", action: home)
          Button(AppText.text("Bookmark"), forumSymbol: library.contains(current) ? "bookmark.fill" : "bookmark") {
            library.toggle(current, title: page?.title ?? current.path)
          }.disabled(page == nil || loading)
          Menu {
            ShareLink(item: current) { Label(AppText.text("Share link"), forumSymbol: "square.and.arrow.up") }
            Button(AppText.text("Site browser"), forumSymbol: "globe") { openBrowser(current) }
            Button(AppText.text("Page diagnostics"), forumSymbol: "ladybug") { showingDiagnostics = true }
            Button(AppText.text("Sign in"), forumSymbol: "person.crop.circle") { openBrowser(session.site.login) }
            if session.site == .south { Button(AppText.text("Blocked authors"), forumSymbol: "person.slash") { showingBlockedAuthors = true } }
            Button(AppText.text("Clear session"), forumSymbol: "person.crop.circle.badge.minus", role: .destructive) { clearSession = true }
          } label: { Image(forumSymbol: "ellipsis") }.disabled(purchasing)
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Button(AppText.text("Previous page"), forumSymbol: "chevron.left") { if let previous = page?.previous { go(to: previous) } }.disabled(page?.previous == nil || loading || purchasing)
          Button { selectingPage = true } label: {
            Text(AppText.format("Page %@", String(error == nil ? page?.pageNumber ?? SitePolicy.pageNumber(current) : SitePolicy.pageNumber(current)))).appFont(.subheadline, weight: .semibold).monospacedDigit()
          }.disabled(page == nil || loading || purchasing).accessibilityLabel(AppText.text("Choose page"))
          Button(AppText.text("Next page"), forumSymbol: "chevron.right") { if let next = page?.next { go(to: next) } }.disabled(page?.next == nil || loading || purchasing)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
          Button { setQuickActions(!quickActionsExpanded) } label: {
            Image(forumSymbol: quickActionsExpanded ? "xmark" : "slider.horizontal.3")
              .contentTransition(.opacity)
          }.disabled(purchasing)
            .accessibilityLabel(AppText.text("Page actions"))
            .accessibilityValue(quickActionsExpanded ? AppText.text("Expanded") : AppText.text("Collapsed"))
        }
  }
  private func activeReader(proxy: ScrollViewProxy) -> some View {
    scrollingReader.toolbar { readerToolbar }
      .forumSheet(isPresented: $selectingPage) {
        if let page = displayPage { PageSelector(page: page) { if let target = page.url(forPage: $0) { go(to: target) } } }
      }
      .forumSheet(isPresented: $showingPinnedThreads, onDismiss: {
        guard let target = selectedPinnedThread else { return }
        selectedPinnedThread = nil
        navigate(target)
      }) {
        SouthPinnedThreadsView(entries: pinnedThreads) { target in
          selectedPinnedThread = target
          showingPinnedThreads = false
        }
      }
      .overlay(alignment: .top) {
        if loading && page != nil { ProgressView().padding(8).background(.regularMaterial, in: Capsule()) }
        else { ReaderEdgeIndicator(edge: .previous, loading: edgeLoading == .previous, failure: edgeFailure) { loadAdjacent(.previous) } }
      }
      .task(id: requestID) {
        guard completedRequestID != requestID else { return }
        let expected = requestID
        let force = forceNextLoad
        let previousID = visibleID
        _ = await load(force: force)
        guard !Task.isCancelled, expected == requestID else { return }
        forceNextLoad = false
        completedRequestID = requestID
        guard error == nil else { return }
        // A fresh entry starts at its title. Only an explicit fragment or a
        // refresh has a requested anchor; cached visibility must not skip it.
        let anchor = force ? previousID ?? "top" : current.fragment ?? "top"
        let visible = page.map { library.document.visibleContent(in: $0) }
        if let first = pinnedThreads.first, anchor == "south-pinned-more" || pinnedThreads.contains(where: { $0.id == anchor }) {
          visibleID = first.id; proxy.scrollTo(first.id, anchor: .top)
        }
        else if anchor != "top", visible?.posts.contains(where: { $0.id == anchor }) == true || visible?.entries.contains(where: { $0.id == anchor }) == true || (anchor == "poll" && visible?.poll != nil) { visibleID = anchor; proxy.scrollTo(anchor, anchor: .top) }
        else if let entry = visible?.entries.first(where: { $0.sectionAnchor == anchor }) { visibleID = entry.id; proxy.scrollTo(entry.id, anchor: .top) }
        else { visibleID = "top"; proxy.scrollTo("top", anchor: .top) }
      }
      .onChange(of: pendingScrollAnchor) { _, anchor in
        guard let anchor else { return }
        proxy.scrollTo(anchor, anchor: .top)
        pendingScrollAnchor = nil
      }
      .overlay(alignment: .bottomTrailing) {
        if quickActionsExpanded {
          ReaderQuickActions(canJump: page != nil && error == nil, busy: loading || purchasing,
            top: { setQuickActions(false); jumpToBoundary(bottom: false, proxy: proxy) },
            bottom: { setQuickActions(false); jumpToBoundary(bottom: true, proxy: proxy) },
            refresh: { setQuickActions(false); reload() })
            .padding(.trailing, 14).padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
      }
      .onAppear {
        isVisible = true
        if page == nil { completedRequestID = nil; requestID = UUID() }
      }
      .onDisappear { quickActionsExpanded = false; purchaseTask?.cancel(); cancelAdjacent(); savePosition(); isVisible = false }
      .onChange(of: purchasing) { _, value in if value { setQuickActions(false) } }
      .onChange(of: canRecordReading) { _, value in if value { recordVisibleProgress() } }
      .onChange(of: visibleID) { old, value in
        guard !loading, error == nil else { return }
        if let previous = readingPages.page(containing: old) { session.pages.savePosition(old, for: previous.url) }
        if let active = readingPages.page(containing: value) {
          if SitePolicy.pageCacheKey(active.url) != SitePolicy.pageCacheKey(current) {
            page = active; url = active.url
            library.remember(active, session: session, checkMaximum: false)
          }
          session.pages.savePosition(value, for: active.url)
        }
      }
      .onChange(of: session.generation) { _, generation in
        guard loadedGeneration != generation else { return }
        page = nil; readingPages.reset(); cancelAdjacent(); error = nil; completedRequestID = nil; posters.cancel()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
        // Keep the immediate return destination while its media viewer is open.
        if !isVisible && media == nil && imageSheet == nil { page = nil; readingPages.reset(); cancelAdjacent(); completedRequestID = nil; posters.cancel() }
      }
  }
  private func routedReader(proxy: ScrollViewProxy) -> some View {
    activeReader(proxy: proxy)
      .navigationDestination(item: $destination) { item in
        // A pushed destination is hosted by NavigationStack, outside the source
        // destination's environment scope. Carry the same site objects explicitly.
        ReaderView(initialURL: item.url, library: library, session: session, home: home)
      }
      .forumSheet(isPresented: $showingBlockedAuthors) { SouthBlockedAuthorsView(library: library) }
      .forumSheet(item: $textSelection) { PostTextSelectionSheet(selection: $0) }
      .forumSheet(isPresented: $showingDiagnostics) {
        ReaderDiagnosticsView(url: diagnosticURL, context: diagnosticContext, session: session)
      }
      .sheet(item: $imageSheet) { item in
        ImageViewerSheet(source: item.source).environmentObject(session)
      }
      .navigationDestination(item: $media) { item in MediaViewerDestination(item: item) }
      .navigationDestination(item: $gofile) { item in GofileBrowserView(url: item.url) }
      .navigationDestination(item: $hostedFiles) { item in HostedFilesView(url: item.url) }
  }
  private func presentedReader(proxy: ScrollViewProxy) -> some View {
    routedReader(proxy: proxy)
      .fullScreenCover(item: $presentation) { item in
        ReaderController(presentation: item, session: session) { captured in
          presentation = nil
          session.endBrowsing()
          loadedGeneration = session.generation
          if let captured, let address = captured["url"] as? String, let target = URL(string: address),
             session.site.accepts(target), let html = captured["html"] as? String {
            if session.site == .south, captured["hasPurchases"] as? Bool == true || captured["hasPoll"] as? Bool == true {
              url = target; page = nil; readingPages.reset(); reload()
              return
            }
            do {
              let parsed = try ForumParser().parse(html, url: target)
              requestID = UUID(); completedRequestID = requestID; forceNextLoad = false; loading = false
              loadedGeneration = session.generation
              session.pages.store(parsed)
              page = parsed; readingPages.reset(parsed); url = target; error = nil
              library.remember(parsed, session: session)
              proxy.scrollTo("top", anchor: .top)
            }
            catch { self.error = AppText.error(error) }
          } else { page = nil; readingPages.reset(); reload() }
        }.ignoresSafeArea()
      }
      .forumConfirmation(AppText.text("Clear forum session?"), isPresented: $clearSession, actions: { [
          ForumDialogAction(AppText.text("Clear session"), role: .destructive) { Task { await session.clear(); reload() } }
        ] })
      .forumAlert(AppText.text("Purchase"), isPresented: Binding(get: { purchaseMessage != nil }, set: { if !$0 { purchaseMessage = nil } }), actions: { [
          ForumDialogAction(AppText.text("OK"), role: .cancel) { purchaseMessage = nil }
        ] }, message: { purchaseMessage ?? "" })
      .forumAlert(AppText.text("Reading library"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } }), actions: { [
          ForumDialogAction(AppText.text("OK"), role: .cancel) { library.error = nil }
        ] }, message: { library.error ?? "" })
      .background(ExternalBrowserPresenter(url: $external).frame(width: 0, height: 0))
  }
  @ViewBuilder private func directoryEntries(in page: ForumPage) -> some View {
    if session.site == .south, page.kind == .threads {
      let pinned = page.entries.filter(\.pinned)
      if let first = pinned.first {
        SouthPinnedThreadsCard(entries: pinned, busy: loading, select: navigate) {
          selectedPinnedThread = nil
          showingPinnedThreads = true
        }.id(first.id)
      }
      ForEach(page.entries.filter { !$0.pinned }) { entry in
        ForumEntryCard(entry: entry, isForum: false, navigate: navigate).id(entry.id)
      }
    } else {
      ForEach(page.entries) { entry in
        ForumEntryCard(entry: entry, isForum: page.kind == .forums, navigate: navigate).id(entry.id)
      }
    }
  }
  private func savePosition() {
    guard loadedGeneration == session.generation, let page else { return }
    readingPages.pages.forEach { session.pages.store($0) }
    session.pages.store(page)
    session.pages.savePosition(visibleID, for: page.url)
  }
  private func recordVisibleProgress() {
    guard canRecordReading, let page = displayPage, page.kind == .posts else { return }
    library.recordVisiblePosts(scrollTracking.visiblePostIDs, in: page)
  }
  private func openAvatar(_ post: ForumPost) {
    guard let url = post.avatarOriginal ?? post.avatar else { return }
    let preview = ForumIcons.image("person.crop.circle").withTintColor(.systemGray, renderingMode: .alwaysOriginal)
    imageSheet = ImageViewerPresentation(source: ImageViewerSource(preview: preview, url: url, loadOriginalOnOpen: true))
  }
  private func setQuickActions(_ expanded: Bool) {
    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { quickActionsExpanded = expanded }
  }
  private func openBrowser(_ target: URL) {
    guard !purchasing, session.site.sameOrigin(target) else { return }
    session.beginBrowsing()
    presentation = .browser(target)
  }
  private func reload() { guard !purchasing else { return }; setQuickActions(false); savePosition(); cancelAdjacent(); forceNextLoad = true; requestID = UUID() }
  private func go(to target: URL) {
    guard !purchasing, session.site.accepts(target), SitePolicy.pageCacheKey(target) != SitePolicy.pageCacheKey(current) else { return }
    setQuickActions(false)
    savePosition()
    cancelAdjacent()
    forceNextLoad = false
    url = target
    requestID = UUID()
  }
  private func navigate(_ url: URL) {
    if let target = GofilePolicy.pageURL(url) { gofile = GofileDestination(url: target) }
    else if HostedFilePolicy.provider(url) != nil { hostedFiles = HostedFilesDestination(url: url) }
    else if session.site.accepts(url) { destination = ReaderDestination(url: url) }
    else { external = url }
  }
  private func play(_ block: BodyBlock) {
    guard let url = block.url, MediaPolicy.allowed(url) else { return }
    if HostedFilePolicy.provider(url) != nil { hostedFiles = HostedFilesDestination(url: url); return }
    media = .video(url, block.direct, session.site.base)
  }
  private func buy(_ offer: SouthPurchaseOffer) {
    guard !loading, edgeLoading == nil else { return }
    startPurchase(selected: offer)
  }
  private func startPurchase(selected offer: SouthPurchaseOffer? = nil, in source: ForumPage? = nil) {
    guard !purchasing, let page = source ?? offer.flatMap({ readingPages.page(offering: $0) }) ?? self.page else { return }
    let blocked = library.document.blockedAuthorIDs
    guard offer != nil || (session.site == .south && page.purchaseOffers(excludingAuthors: blocked).contains(where: \.isFree)) else { return }
    purchasing = true
    purchaseMessage = nil
    let expected = requestID
    let epoch = session.generation
    purchaseTask = Task { @MainActor in
      defer { purchasing = false; purchaseTask = nil }
      do {
        let update: SouthPurchaseService.Update = { fresh in
          guard !Task.isCancelled, expected == requestID, epoch == session.generation else { return }
          let position = visibleID
          let merged = fresh.preservingPurchaseContent(from: readingPages.page(for: fresh.url) ?? page)
          readingPages.replace(merged)
          readingPages.trim(keeping: current)
          session.pages.store(merged)
          if SitePolicy.pageCacheKey(current) == SitePolicy.pageCacheKey(merged.url) {
            self.page = merged; url = merged.url
            session.pages.savePosition(position, for: merged.url)
            library.remember(merged, session: session, checkMaximum: false)
          }
        }
        var result = try await session.purchaseContent(in: page, selected: offer, excludingAuthors: blocked, onUpdate: update)
        if offer != nil, result.message == nil, result.page.purchaseOffers(excludingAuthors: blocked).contains(where: \.isFree) {
          result = try await session.purchaseContent(in: result.page, excludingAuthors: blocked, onUpdate: update)
        }
        guard !Task.isCancelled, expected == requestID, epoch == session.generation else { return }
        purchaseMessage = result.message
      } catch {
        guard !Task.isCancelled, expected == requestID, epoch == session.generation else { return }
        purchaseMessage = AppText.error(error)
      }
    }
  }
  @MainActor private func load(force: Bool) async -> String? {
    guard !purchasing else { return visibleID }
    let expected = requestID
    let epoch = session.generation
    scrollTracking.visiblePostIDs = []
    loading = true
    error = nil
    defer { if requestID == expected { loading = false } }
    if !force, let cached = session.pages.value(for: current) {
      page = cached.page; readingPages.reset(cached.page); url = cached.page.url; loadedGeneration = epoch
      library.remember(cached.page, session: session, checkMaximum: false)
      startPurchase()
      return cached.visibleID
    }
    do {
      let parsed = try await session.load(current, cacheResult: true)
      guard !Task.isCancelled, requestID == expected, epoch == session.generation else { return nil }
      posters.cancel()
      loadedGeneration = epoch
      page = parsed; readingPages.reset(parsed); url = parsed.url; library.remember(parsed, session: session)
      startPurchase()
    } catch {
      guard !Task.isCancelled, requestID == expected, epoch == session.generation else { return nil }
      self.error = AppText.error(error)
    }
    return nil
  }
  private func checkEdgeDrag(phase: ScrollPhase? = nil) {
    guard isVisible, !loading, !purchasing, edgeLoading == nil, error == nil else { return }
    let pull = scrollTracking.pull
    let phase = phase ?? scrollPhase
    if let edge = scrollTracking.trigger.update(topPull: Double(pull.top), remaining: Double(pull.remaining), offset: Double(pull.offset),
                                    interacting: phase == .interacting, decelerating: phase == .decelerating,
                                    previous: readingPages.target(.previous) != nil, next: readingPages.target(.next) != nil) {
      loadAdjacent(edge)
    }
  }
  private var diagnosticContext: String {
    let previous = readingPages.target(.previous).map { ReaderDiagnostics.address($0.absoluteString) } ?? "none"
    let next = readingPages.target(.next).map { ReaderDiagnostics.address($0.absoluteString) } ?? "none"
    let pull = scrollTracking.pull
    return "Loaded pages: \(readingPages.pages.map(\.pageNumber))\nPrevious: \(previous)\nNext: \(next)\n" +
      "Edge pull: top=\(pull.top), bottom=\(pull.bottom); remaining=\(pull.remaining), offset=\(pull.offset); phase=\(scrollPhase)\n" +
      "Last drag peak: top=\(scrollTracking.peakTopPull), bottom=\(scrollTracking.peakBottomPull); edge event=\(lastEdgeEvent)\n" +
      "Reader error: \(error ?? "none")\nEdge error: \(edgeFailure?.message ?? "none")"
  }
  private var diagnosticURL: URL {
    edgeFailure.flatMap { readingPages.target($0.edge) } ?? current
  }
  private func loadAdjacent(_ edge: ReaderEdge) {
    guard !loading, !purchasing, edgeLoading == nil, let target = readingPages.target(edge) else { return }
    lastEdgeEvent = "Requested \(edge), page \(SitePolicy.pageNumber(target))"
    edgeFailure = nil
    edgeLoading = edge
    let token = UUID()
    edgeRequestID = token
    let epoch = session.generation
    let expected = requestID
    edgeTask = Task { @MainActor in
      defer {
        if edgeRequestID == token {
          edgeTask = nil
          if pendingPage == nil { edgeLoading = nil }
        }
      }
      do {
        let incoming: ForumPage
        if let cached = session.pages.value(for: target) { incoming = cached.page }
        else { incoming = try await session.load(target) }
        guard !Task.isCancelled, token == edgeRequestID, expected == requestID, epoch == session.generation else { return }
        guard SitePolicy.pageCacheKey(incoming.url) == SitePolicy.pageCacheKey(target), incoming.kind == page?.kind else { throw ReaderFailure.unsupported }
        pendingPage = incoming
        lastEdgeEvent = "Received \(edge), page \(incoming.pageNumber)"
        applyAdjacentPage()
      } catch {
        guard !Task.isCancelled, token == edgeRequestID, expected == requestID, epoch == session.generation else { return }
        edgeFailure = ReaderEdgeFailure(edge: edge, message: AppText.error(error))
        lastEdgeEvent = "Failed \(edge): \(AppText.error(error))"
      }
    }
  }
  private func applyAdjacentPage() {
    guard let incoming = pendingPage, let edge = edgeLoading, let page else { return }
    // Appending below the viewport can continue the same drag or flick.
    // Prepending, or evicting content above it, needs a settled anchor.
    guard edge == .next || scrollPhase == .idle else { return }
    let visible = library.document.visibleContent(in: readingPages.combined(active: page))
    let fallback = visible.posts.first?.id ?? visible.entries.first?.id
    // The global title sentinel changes meaning when an older page is
    // prepended. Preserve the old page's content instead of the new global top.
    let anchor = edge == .previous && (visibleID == nil || visibleID == "top") ? fallback ?? "top" : visibleID ?? "top"
    let protected = readingPages.page(containing: anchor)?.url ?? (fallback == nil ? incoming.url : page.url)
    let priorFirst = readingPages.pages.first?.url
    var updated = readingPages
    guard updated.insert(incoming, at: edge, keeping: protected) else {
      pendingPage = nil; edgeLoading = nil
      edgeFailure = ReaderEdgeFailure(edge: edge, message: AppText.text("Could not join this page. Try again."))
      return
    }
    guard scrollPhase == .idle || updated.pages.first?.url == priorFirst else { return }
    session.pages.store(updated.page(for: incoming.url) ?? incoming)
    lastEdgeEvent = "Joined \(edge), page \(incoming.pageNumber)"
    let active = updated.page(for: protected) ?? page
    let changedPage = SitePolicy.pageCacheKey(current) != SitePolicy.pageCacheKey(active.url)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      readingPages = updated
      self.page = active; url = active.url
      pendingPage = nil
      edgeLoading = nil
      // Appending to an existing page must not snap to its first post. Only
      // preserve a content anchor when inserting/removing content above it.
      if edge == .previous || updated.pages.first?.url != priorFirst {
        pendingScrollAnchor = anchor
      }
    }
    if changedPage { library.remember(active, session: session, checkMaximum: false) }
    if readingPages.page(for: incoming.url) != nil { startPurchase(in: incoming) }
  }
  private func jumpToBoundary(bottom: Bool, proxy: ScrollViewProxy) {
    guard let page else { return }
    let visible = library.document.visibleContent(in: page)
    let candidates = page.kind == .posts ? visible.posts.map(\.id) : visible.entries.map(\.id)
    let ids = candidates.filter { id in
      readingPages.page(containing: id).map { SitePolicy.pageCacheKey($0.url) == SitePolicy.pageCacheKey(page.url) } ?? true
    }
    let atFirstLoadedPage = readingPages.pages.first.map { SitePolicy.pageCacheKey($0.url) == SitePolicy.pageCacheKey(page.url) } ?? true
    let target = bottom ? ids.last ?? "top" : atFirstLoadedPage ? "top" : ids.first ?? "top"
    proxy.scrollTo(target, anchor: bottom ? .bottom : .top)
  }
  private func cancelAdjacent() {
    scrollTracking.trigger.endDrag()
    edgeRequestID = UUID()
    edgeTask?.cancel(); edgeTask = nil
    pendingPage = nil; edgeLoading = nil; edgeFailure = nil
  }
}

enum ReaderPresentation: Identifiable {
  case browser(URL)
  var id: String {
    switch self { case .browser(let url): return "browser:" + url.absoluteString }
  }
}
struct ReaderController: UIViewControllerRepresentable {
  let presentation: ReaderPresentation
  let session: ForumSession
  let completion: ([String: Any]?) -> Void
  func makeUIViewController(context: Context) -> UINavigationController {
    switch presentation {
    case .browser(let url):
      return UINavigationController(rootViewController: ForumBrowserController(url: url, session: session, completion: completion))
    }
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
