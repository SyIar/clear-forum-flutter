import SwiftUI
import WebKit

struct ReaderView: View {
  let initialURL: URL
  var home: () -> Void
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
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
  @StateObject private var posters = PosterStore()
  private var current: URL { url ?? initialURL }
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
          } else if let page {
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
              ForEach(page.posts) { post in
                PostCard(post: post, posters: posters, navigate: navigate, play: play, openImage: { media = .image(UUID(), $0) }).id(post.id)
              }
            } else {
              ForEach(page.entries) { entry in
                ForumEntryCard(entry: entry, isForum: page.kind == .forums, navigate: navigate).id(entry.id)
              }
              if page.entries.isEmpty { ContentUnavailableView("No threads yet", systemImage: "tray") }
            }
          } else { ProgressView("Loading page...").frame(maxWidth: .infinity).padding(.top, 100) }
        }.scrollTargetLayout().padding(.horizontal, 12).padding(.bottom, 14)
      }
      .scrollPosition(id: $visibleID, anchor: .top)
      .background(Color(uiColor: .systemGroupedBackground))
      .refreshable { _ = await load(force: true) }
      .navigationTitle(page?.kind == .posts ? "Thread" : "Forums").navigationBarTitleDisplayMode(.inline)
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
            Button("Clear session", systemImage: "person.crop.circle.badge.minus", role: .destructive) { clearSession = true }
          } label: { Image(systemName: "ellipsis") }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Button("Previous page", systemImage: "chevron.left") { if let previous = page?.previous { go(to: previous) } }.disabled(page?.previous == nil || loading)
          Button { selectingPage = true } label: {
            Text("Page \(page?.pageNumber ?? 1)").font(.subheadline.weight(.semibold)).monospacedDigit()
          }.disabled(page == nil || loading || page?.pageCount == 1).accessibilityLabel("Choose page")
          Button("Next page", systemImage: "chevron.right") { if let next = page?.next { go(to: next) } }.disabled(page?.next == nil || loading)
        }
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
          Button("Refresh", systemImage: "arrow.clockwise") { reload() }.disabled(loading)
        }
      }
      .sheet(isPresented: $selectingPage) {
        if let page { PageSelector(page: page) { if let target = page.url(forPage: $0) { go(to: target) } } }
      }
      .overlay(alignment: .top) { if loading && page != nil { ProgressView().padding(8).background(.regularMaterial, in: Capsule()) } }
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
        if anchor != "top", page?.posts.contains(where: { $0.id == anchor }) == true || page?.entries.contains(where: { $0.id == anchor }) == true { visibleID = anchor }
        else if let entry = page?.entries.first(where: { $0.sectionAnchor == anchor }) { visibleID = entry.id }
        else { visibleID = "top"; proxy.scrollTo("top", anchor: .top) }
      }
      .onAppear {
        isVisible = true
        if page == nil { completedRequestID = nil; requestID = UUID() }
      }
      .onDisappear { savePosition(); isVisible = false }
      .onChange(of: visibleID) { _, value in
        if !loading, let page { session.pages.savePosition(value, for: page.url) }
      }
      .onChange(of: session.generation) { _, generation in
        guard loadedGeneration != generation else { return }
        page = nil; error = nil; completedRequestID = nil; posters.cancel()
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
        // Keep the immediate return destination while its media viewer is open.
        if !isVisible && media == nil { page = nil; completedRequestID = nil; posters.cancel() }
      }
      .navigationDestination(item: $destination) { item in ReaderView(initialURL: item.url, home: home) }
      .background(MediaViewerPresenter(item: $media))
      .fullScreenCover(item: $presentation) { item in
        ReaderController(presentation: item, session: session) { captured in
          presentation = nil
          session.endBrowsing()
          loadedGeneration = session.generation
          if let captured, let address = captured["url"] as? String, let target = URL(string: address),
             session.site.accepts(target), let html = captured["html"] as? String {
            do {
              let parsed = try ForumParser().parse(html, url: target)
              requestID = UUID(); completedRequestID = requestID; forceNextLoad = false; loading = false
              loadedGeneration = session.generation
              session.pages.store(parsed)
              page = parsed; url = target; error = nil
              library.remember(parsed, session: session)
              proxy.scrollTo("top", anchor: .top)
            }
            catch { self.error = error.localizedDescription }
          } else { page = nil; reload() }
        }.ignoresSafeArea()
      }
      .confirmationDialog("Clear forum session?", isPresented: $clearSession, titleVisibility: .visible) {
        Button("Clear session", role: .destructive) { Task { await session.clear(); reload() } }
      }
      .confirmationDialog("Open external link?", isPresented: Binding(get: { external != nil }, set: { if !$0 { external = nil } }), titleVisibility: .visible) {
        if let external { Link("Open \(external.host ?? "link")", destination: external) }
      }
    }
  }
  private func savePosition() {
    guard loadedGeneration == session.generation, let page else { return }
    session.pages.store(page)
    session.pages.savePosition(visibleID, for: page.url)
  }
  private func openBrowser(_ target: URL) {
    guard session.site.sameOrigin(target) else { return }
    session.beginBrowsing()
    presentation = .browser(target)
  }
  private func reload() { savePosition(); forceNextLoad = true; requestID = UUID() }
  private func go(to target: URL) {
    guard session.site.accepts(target), SitePolicy.pageCacheKey(target) != SitePolicy.pageCacheKey(current) else { return }
    savePosition()
    forceNextLoad = false
    url = target
    requestID = UUID()
  }
  private func navigate(_ url: URL) {
    if session.site.accepts(url) { destination = ReaderDestination(url: url) }
    else { external = url }
  }
  private func play(_ block: BodyBlock) {
    guard let url = block.url, MediaPolicy.allowed(url) else { return }
    media = .video(url, block.direct, session.site.base)
  }
  @MainActor private func load(force: Bool) async -> String? {
    let expected = requestID
    let epoch = session.generation
    loading = true
    error = nil
    defer { if requestID == expected { loading = false } }
    if !force, let cached = session.pages.value(for: current) {
      page = cached.page; url = cached.page.url; loadedGeneration = epoch
      library.remember(cached.page, session: session, checkMaximum: false)
      return cached.visibleID
    }
    do {
      let parsed = try await session.load(current, cacheResult: true)
      guard !Task.isCancelled, requestID == expected, epoch == session.generation else { return nil }
      posters.cancel()
      loadedGeneration = epoch
      page = parsed; url = parsed.url; library.remember(parsed, session: session)
    } catch {
      guard !Task.isCancelled, requestID == expected, epoch == session.generation else { return nil }
      self.error = error.localizedDescription
    }
    return nil
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
