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
  @State private var presentation: ReaderPresentation?
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
              Button("Site browser") { presentation = .browser(current) }.buttonStyle(.bordered)
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
            Text(page.title).font(.title2.bold()).padding(.horizontal, 4)
            Text(page.loggedIn ? "Signed in" : "Guest").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            if page.kind == .posts {
              ForEach(page.posts) { post in
                PostCard(post: post, posters: posters, navigate: navigate, play: play).id(post.id)
              }
            } else {
              ForEach(page.entries) { entry in
                Button { destination = ReaderDestination(url: entry.url) } label: {
                  HStack(spacing: 10) {
                    if let thumbnail = entry.thumbnail {
                      ForumThumbnail(url: thumbnail, compact: entry.pinned)
                    } else {
                      Image(systemName: entry.pinned ? "pin.fill" : (page.kind == .forums ? "folder" : "text.bubble")).foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                      Text(entry.title).font(entry.pinned ? .subheadline : .body).lineLimit(entry.pinned ? 1 : 3).foregroundStyle(.primary)
                      if !entry.pinned && !entry.subtitle.isEmpty { Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                  }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).id(entry.id)
              }
              if page.entries.isEmpty { ContentUnavailableView("No threads yet", systemImage: "tray") }
            }
          } else { ProgressView("Loading page...").frame(maxWidth: .infinity).padding(.top, 100) }
        }.padding(.horizontal, 12).padding(.bottom, 14)
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .refreshable { await load() }
      .navigationTitle(page?.kind == .posts ? "Thread" : "Forums").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Home", systemImage: "house", action: home)
          Button("Bookmark", systemImage: library.contains(current) ? "bookmark.fill" : "bookmark") {
            library.toggle(current, title: page?.title ?? current.path)
          }.disabled(page == nil || loading)
          Menu {
            ShareLink(item: current) { Label("Share link", systemImage: "square.and.arrow.up") }
            Button("Site browser", systemImage: "globe") { presentation = .browser(current) }
            Button("Sign in", systemImage: "person.crop.circle") { presentation = .browser(SitePolicy.base.appendingPathComponent("login/")) }
            Button("Clear session", systemImage: "person.crop.circle.badge.minus", role: .destructive) { clearSession = true }
          } label: { Image(systemName: "ellipsis") }
        }
        ToolbarItemGroup(placement: .bottomBar) {
          Button("Previous page", systemImage: "chevron.left") { if let previous = page?.previous { url = previous; reload() } }.disabled(page?.previous == nil || loading)
          Spacer()
          Text("Page \(page?.pageNumber ?? 1)").font(.subheadline.weight(.semibold)).monospacedDigit()
          Spacer()
          Button("Refresh", systemImage: "arrow.clockwise") { reload() }.disabled(loading)
          Button("Next page", systemImage: "chevron.right") { if let next = page?.next { url = next; reload() } }.disabled(page?.next == nil || loading)
        }
      }
      .overlay(alignment: .top) { if loading && page != nil { ProgressView().padding(8).background(.regularMaterial, in: Capsule()) } }
      .task(id: requestID) {
        await load()
        guard !Task.isCancelled else { return }
        let anchor = current.fragment ?? "top"
        if anchor != "top", page?.posts.contains(where: { $0.id == anchor }) == true { proxy.scrollTo(anchor, anchor: .top) }
        else if let entry = page?.entries.first(where: { $0.sectionAnchor == anchor }) { proxy.scrollTo(entry.id, anchor: .top) }
        else { proxy.scrollTo("top", anchor: .top) }
      }
      .navigationDestination(item: $destination) { item in ReaderView(initialURL: item.url, home: home) }
      .fullScreenCover(item: $presentation) { item in
        ReaderController(presentation: item, store: session.store) { captured in
          presentation = nil
          if let captured, let address = captured["url"] as? String, let target = URL(string: address),
             SitePolicy.readable(target), let html = captured["html"] as? String {
            do { let parsed = try ForumParser().parse(html, url: target); page = parsed; url = target; error = nil; library.remember(parsed, session: session); proxy.scrollTo("top", anchor: .top) }
            catch { self.error = error.localizedDescription }
          } else if case .browser = item { reload() }
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
  private func reload() { requestID = UUID() }
  private func navigate(_ url: URL) {
    if SitePolicy.readable(url) { destination = ReaderDestination(url: url) }
    else { external = url }
  }
  private func play(_ block: BodyBlock) {
    guard let url = block.url, MediaPolicy.allowed(url) else { return }
    presentation = .media(url, block.direct)
  }
  @MainActor private func load() async {
    let expected = requestID
    loading = true
    error = nil
    do {
      let parsed = try await session.load(current)
      guard !Task.isCancelled, requestID == expected else { return }
      posters.cancel()
      page = parsed; url = parsed.url; library.remember(parsed, session: session)
    } catch {
      guard !Task.isCancelled, requestID == expected else { return }
      self.error = error.localizedDescription
    }
    if requestID == expected { loading = false }
  }
}

enum ReaderPresentation: Identifiable {
  case browser(URL), media(URL, Bool)
  var id: String {
    switch self { case .browser(let url): return "browser:" + url.absoluteString
    case .media(let url, let direct): return "media:\(direct):" + url.absoluteString }
  }
}
struct ReaderController: UIViewControllerRepresentable {
  let presentation: ReaderPresentation
  let store: WKWebsiteDataStore
  let completion: ([String: Any]?) -> Void
  func makeUIViewController(context: Context) -> UINavigationController {
    switch presentation {
    case .browser(let url):
      return UINavigationController(rootViewController: ForumBrowserController(url: url, store: store, completion: completion))
    case .media(let url, let direct):
      return MediaNavigationController(player: MediaPlayerController(url: url, direct: direct) { completion(nil) })
    }
  }
  func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
