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
  @State private var isVisible = false
  @State private var loadedGeneration = -1
  @State private var selectingPage = false
  @State private var presentation: ReaderPresentation?
  @State private var media: MediaViewerItem?
  @State private var clearSession = false
  @State private var destination: ReaderDestination?
  @State private var external: URL?
  @State private var gofile: GofileDestination?
  @State private var purchasing = false
  @State private var purchaseMessage: String?
  @State private var purchaseTask: Task<Void, Never>?
  @State private var authorSelection: SouthAuthorSelection?
  @State private var showingAuthorActions = false
  @State private var showingBlockedAuthors = false
  @State private var showingPinnedThreads = false
  @State private var selectedPinnedThread: URL?
  @State private var readingPages = ReaderPageWindow()
  @State private var edgeTrigger = ReaderEdgeTrigger()
  @State private var edgePull = ReaderEdgePull()
  @State private var scrollPhase: ScrollPhase = .idle
  @State private var edgeLoading: ReaderEdge?
  @State private var edgeFailure: ReaderEdgeFailure?
  @State private var edgeTask: Task<Void, Never>?
  @State private var edgeRequestID = UUID()
  @State private var pendingPage: ForumPage?
  @StateObject private var posters = PosterStore()
  private var current: URL { url ?? initialURL }
  private var displayPage: ForumPage? { page.map { readingPages.combined(active: $0) } }
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
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          Color.clear.frame(height: 0).id("top")
          if let error {
            ContentUnavailableView {
              Label("Could not load page", systemImage: "wifi.exclamationmark")
            } description: { Text(error) } actions: {
              Button("Retry") { reload() }.buttonStyle(.borderedProminent)
              Button("Site browser") { openBrowser(current) }.buttonStyle(.bordered)
            }
          } else if let page = displayPage {
            let visible = library.document.visibleContent(in: page)
            if !page.breadcrumbs.isEmpty {
              ScrollView(.horizontal) {
                HStack(spacing: 6) {
                  ForEach(Array(page.breadcrumbs.enumerated()), id: \.offset) { index, entry in
                    if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary) }
                    Button(entry.title) { navigate(entry.url) }
                      .font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(.blue)
                      .padding(.horizontal, 6).frame(minHeight: 36)
                  }
                }
              }.scrollIndicators(.hidden).accessibilityLabel("Forum navigation")
            }
            if !page.tags.isEmpty { ForumTagStrip(tags: page.tags, navigate: navigate) }
            Text(page.title).font(.title2.bold()).padding(.horizontal, 4)
            Text(page.loggedIn.map { $0 ? "Signed in" : "Guest" } ?? "Clean view").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            if page.kind == .posts {
              if let poll = visible.poll {
                SouthPollCard(poll: poll, busy: loading || purchasing) { openBrowser(page.url) }.id("poll")
              }
              ForEach(visible.posts) { post in
                PostCard(post: post, posters: posters, navigate: navigate, play: play, openImage: { media = .image(UUID(), $0) }, purchase: buy,
                         purchasing: purchasing || loading,
                         authorFilterActive: post.authorFilterURL.map { SouthSitePolicy.authorID($0) == SouthSitePolicy.authorID(page.url) } ?? false,
                         authorAction: authorAction(for: post)).id(post.id)
              }
              if visible.posts.isEmpty { ContentUnavailableView("No visible replies", systemImage: "person.slash") }
            } else {
              directoryEntries(in: visible)
              if visible.entries.isEmpty { ContentUnavailableView(page.entries.isEmpty ? "No threads yet" : "No visible threads", systemImage: "tray") }
            }
          } else { ProgressView("Loading page...").frame(maxWidth: .infinity).padding(.top, 100) }
        }.scrollTargetLayout().padding(.horizontal, 12).padding(.bottom, 14)
      }
      .scrollPosition(id: $visibleID, anchor: .top)
      .scrollBounceBehavior(.always, axes: .vertical)
      .onScrollGeometryChange(for: ReaderEdgePull.self) { ReaderEdgePull($0) } action: { _, pull in
        edgePull = pull
        checkEdgeDrag()
      }
      .onScrollPhaseChange { old, phase in
        scrollPhase = phase
        if phase == .tracking || (phase == .interacting && old != .tracking) { edgeTrigger.beginDrag() }
        if phase == .interacting { checkEdgeDrag() }
        if phase == .idle { applyAdjacentPage() }
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle(SouthSitePolicy.topicAuthorID(current) != nil ? "Author threads" : page?.kind == .posts ? "Thread" : "Forums").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Home", systemImage: "house", action: home)
          Button("Bookmark", systemImage: library.contains(current) ? "bookmark.fill" : "bookmark") {
            library.toggle(current, title: page?.title ?? current.path)
          }.disabled(page == nil || loading)
          Menu {
            ShareLink(item: current) { Label("Share link", systemImage: "square.and.arrow.up") }
            Button("Site browser", systemImage: "globe") { openBrowser(current) }
            Button("Sign in", systemImage: "person.crop.circle") { openBrowser(session.site.login) }
            if session.site == .south { Button("Blocked authors", systemImage: "person.slash") { showingBlockedAuthors = true } }
            Button("Clear session", systemImage: "person.crop.circle.badge.minus", role: .destructive) { clearSession = true }
          } label: { Image(systemName: "ellipsis") }.disabled(purchasing)
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Button("Previous page", systemImage: "chevron.left") { if let previous = page?.previous { go(to: previous) } }.disabled(page?.previous == nil || loading || purchasing)
          Button { selectingPage = true } label: {
            Text("Page \(page?.pageNumber ?? 1)").font(.subheadline.weight(.semibold)).monospacedDigit()
          }.disabled(page == nil || loading || purchasing || page?.pageCount == 1).accessibilityLabel("Choose page")
          Button("Next page", systemImage: "chevron.right") { if let next = page?.next { go(to: next) } }.disabled(page?.next == nil || loading || purchasing)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
          Button("Refresh", systemImage: "arrow.clockwise") { reload() }.disabled(loading || purchasing)
        }
      }
      .sheet(isPresented: $selectingPage) {
        if let page = displayPage { PageSelector(page: page) { if let target = page.url(forPage: $0) { go(to: target) } } }
      }
      .sheet(isPresented: $showingPinnedThreads, onDismiss: {
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
      .overlay(alignment: .bottom) {
        ReaderEdgeIndicator(edge: .next, loading: edgeLoading == .next, failure: edgeFailure) { loadAdjacent(.next) }.padding(.bottom, 6)
      }
      .task(id: requestID) {
        guard completedRequestID != requestID else { return }
        let expected = requestID
        let force = forceNextLoad
        let previousID = visibleID
        let restoredID = await load(force: force)
        guard !Task.isCancelled, expected == requestID else { return }
        forceNextLoad = false
        completedRequestID = requestID
        guard error == nil else { return }
        let anchor = force ? previousID ?? "top" : current.fragment ?? restoredID ?? "top"
        let visible = page.map { library.document.visibleContent(in: $0) }
        if pinnedThreads.dropFirst(2).contains(where: { $0.id == anchor }) { visibleID = "south-pinned-more" }
        else if anchor != "top", visible?.posts.contains(where: { $0.id == anchor }) == true || visible?.entries.contains(where: { $0.id == anchor }) == true || (anchor == "poll" && visible?.poll != nil) { visibleID = anchor }
        else if let entry = visible?.entries.first(where: { $0.sectionAnchor == anchor }) { visibleID = entry.id }
        else { visibleID = "top"; proxy.scrollTo("top", anchor: .top) }
      }
      .onAppear {
        isVisible = true
        if page == nil { completedRequestID = nil; requestID = UUID() }
      }
      .onDisappear { purchaseTask?.cancel(); cancelAdjacent(); savePosition(); isVisible = false }
      .onChange(of: visibleID) { old, value in
        guard !loading else { return }
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
        if !isVisible && media == nil { page = nil; readingPages.reset(); cancelAdjacent(); completedRequestID = nil; posters.cancel() }
      }
      .navigationDestination(item: $destination) { item in
        // A pushed destination is hosted by NavigationStack, outside the source
        // destination's environment scope. Carry the same site objects explicitly.
        ReaderView(initialURL: item.url, library: library, session: session, home: home)
      }
      .sheet(isPresented: $showingBlockedAuthors) { SouthBlockedAuthorsView(library: library) }
      .confirmationDialog(authorSelection?.post.author ?? "Author", isPresented: $showingAuthorActions, titleVisibility: .visible, presenting: authorSelection) { selection in
        Button("View full-size avatar") { openAvatar(selection) }.disabled(selection.post.avatarOriginal == nil && selection.post.avatar == nil)
        Button("View author threads") {
          if let id = selection.post.authorID, let target = SouthSitePolicy.authorTopics(id) { navigate(target) }
        }.disabled(selection.post.authorID.flatMap(SouthSitePolicy.authorTopics) == nil)
        Button("Block author", role: .destructive) {
          if let id = selection.post.authorID { library.change { $0.blockAuthor(id: id, name: selection.post.author) } }
        }.disabled(purchasing || (selection.post.authorID.map { !SouthSitePolicy.validAuthorID($0) } ?? true))
        Button("Cancel", role: .cancel) {}
      }
      .navigationDestination(item: $media) { item in MediaViewerDestination(item: item) }
      .navigationDestination(item: $gofile) { item in GofileBrowserView(url: item.url) }
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
            catch { self.error = error.localizedDescription }
          } else { page = nil; readingPages.reset(); reload() }
        }.ignoresSafeArea()
      }
      .confirmationDialog("Clear forum session?", isPresented: $clearSession, titleVisibility: .visible) {
        Button("Clear session", role: .destructive) { Task { await session.clear(); reload() } }
      }
      .alert("Purchase", isPresented: Binding(get: { purchaseMessage != nil }, set: { if !$0 { purchaseMessage = nil } })) {
        Button("OK", role: .cancel) { purchaseMessage = nil }
      } message: { Text(purchaseMessage ?? "") }
      .alert("Reading library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
        Button("OK", role: .cancel) { library.error = nil }
      } message: { Text(library.error ?? "") }
      .background(ExternalBrowserPresenter(url: $external).frame(width: 0, height: 0))
    }
    .environmentObject(library)
    .environmentObject(session)
  }
  @ViewBuilder private func directoryEntries(in page: ForumPage) -> some View {
    if session.site == .south, page.kind == .threads {
      let pinned = page.entries.filter(\.pinned)
      ForEach(pinned.prefix(2)) { entry in
        ForumEntryCard(entry: entry, isForum: false, navigate: navigate).id(entry.id)
      }
      if pinned.count > 2 {
        HStack {
          Spacer()
          Button { selectedPinnedThread = nil; showingPinnedThreads = true } label: {
            Image(systemName: "ellipsis").font(.headline).frame(width: 40, height: 28)
          }.buttonStyle(.glass).buttonBorderShape(.capsule)
            .disabled(loading).accessibilityLabel("Show all \(pinned.count) pinned threads")
          Spacer()
        }.id("south-pinned-more")
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
  private func openAvatar(_ selection: SouthAuthorSelection) {
    guard let url = selection.post.avatarOriginal ?? selection.post.avatar else { return }
    let preview = selection.preview ?? UIImage(systemName: "person.crop.circle")?.withTintColor(.systemGray, renderingMode: .alwaysOriginal) ?? UIImage()
    media = .image(UUID(), ImageViewerSource(preview: preview, url: url, loadOriginalOnOpen: true))
  }
  private func authorAction(for post: ForumPost) -> ((UIImage?) -> Void)? {
    guard session.site == .south else { return nil }
    return { preview in
      authorSelection = SouthAuthorSelection(post: post, preview: preview)
      showingAuthorActions = true
    }
  }
  private func openBrowser(_ target: URL) {
    guard !purchasing, session.site.sameOrigin(target) else { return }
    session.beginBrowsing()
    presentation = .browser(target)
  }
  private func reload() { guard !purchasing else { return }; savePosition(); cancelAdjacent(); forceNextLoad = true; requestID = UUID() }
  private func go(to target: URL) {
    guard !purchasing, session.site.accepts(target), SitePolicy.pageCacheKey(target) != SitePolicy.pageCacheKey(current) else { return }
    savePosition()
    cancelAdjacent()
    forceNextLoad = false
    url = target
    requestID = UUID()
  }
  private func navigate(_ url: URL) {
    if let target = GofilePolicy.pageURL(url) { gofile = GofileDestination(url: target) }
    else if session.site.accepts(url) { destination = ReaderDestination(url: url) }
    else { external = url }
  }
  private func play(_ block: BodyBlock) {
    guard let url = block.url, MediaPolicy.allowed(url) else { return }
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
        purchaseMessage = error.localizedDescription
      }
    }
  }
  @MainActor private func load(force: Bool) async -> String? {
    guard !purchasing else { return visibleID }
    let expected = requestID
    let epoch = session.generation
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
      self.error = error.localizedDescription
    }
    return nil
  }
  private func checkEdgeDrag() {
    guard isVisible, !loading, !purchasing, edgeLoading == nil, error == nil else { return }
    if let edge = edgeTrigger.update(topPull: Double(edgePull.top), bottomPull: Double(edgePull.bottom),
                                    interacting: scrollPhase == .interacting,
                                    previous: readingPages.target(.previous) != nil, next: readingPages.target(.next) != nil) {
      loadAdjacent(edge)
    }
  }
  private func loadAdjacent(_ edge: ReaderEdge) {
    guard !loading, !purchasing, edgeLoading == nil, let target = readingPages.target(edge) else { return }
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
        if scrollPhase == .idle { applyAdjacentPage() }
      } catch {
        guard !Task.isCancelled, token == edgeRequestID, expected == requestID, epoch == session.generation else { return }
        edgeFailure = ReaderEdgeFailure(edge: edge, message: error.localizedDescription)
      }
    }
  }
  private func applyAdjacentPage() {
    guard let incoming = pendingPage, let edge = edgeLoading, let page else { return }
    // Commit only after the drag/bounce ends, keeping a real content ID pinned.
    // New pages reuse existing post/block identities instead of rebuilding them.
    let visible = library.document.visibleContent(in: readingPages.combined(active: page))
    let fallback = visible.posts.first?.id ?? visible.entries.first?.id
    let anchor = visibleID.flatMap { $0 == "top" ? fallback : $0 } ?? fallback
    let protected = readingPages.page(containing: anchor)?.url ?? (fallback == nil ? incoming.url : page.url)
    var updated = readingPages
    guard updated.insert(incoming, at: edge, keeping: protected) else {
      pendingPage = nil; edgeLoading = nil
      edgeFailure = ReaderEdgeFailure(edge: edge, message: "Could not join this page. Try again.")
      return
    }
    session.pages.store(updated.page(for: incoming.url) ?? incoming)
    let active = updated.page(for: protected) ?? page
    let changedPage = SitePolicy.pageCacheKey(current) != SitePolicy.pageCacheKey(active.url)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      visibleID = anchor
      readingPages = updated
      self.page = active; url = active.url
      pendingPage = nil
      edgeLoading = nil
    }
    if changedPage { library.remember(active, session: session, checkMaximum: false) }
    if readingPages.page(for: incoming.url) != nil { startPurchase(in: incoming) }
  }
  private func cancelAdjacent() {
    edgeRequestID = UUID()
    edgeTask?.cancel(); edgeTask = nil
    pendingPage = nil; edgeLoading = nil; edgeFailure = nil
  }
}

private struct SouthAuthorSelection {
  let post: ForumPost
  let preview: UIImage?
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
