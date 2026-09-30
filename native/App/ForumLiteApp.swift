import SwiftUI

@main
struct ForumLiteApp: App {
  @StateObject private var downloads = VideoDownloadManager.shared
  @StateObject private var gofileDownloads = GofileDownloadManager.shared
  @StateObject private var hostedDownloads = HostedDownloadManager.shared
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var simpLibrary = LibraryStore(site: .simp)
  @StateObject private var southLibrary = LibraryStore(site: .south)
  @StateObject private var simpSession = ForumSession(site: .simp)
  @StateObject private var southSession = ForumSession(site: .south)
  @State private var path: [ForumDestination] = []
  init() { AppTypography.configureNavigation() }
  var body: some Scene {
    WindowGroup {
      NavigationStack(path: $path) {
        ForumSelectionView()
          .navigationDestination(for: ForumDestination.self) { destination in
            let site = destination.site
            Group {
              switch destination {
              case .home:
                HomeView(path: $path)
              case .search:
                ForumSearchView { path.append(.reader($0)) }
              case .reader(let url):
                ReaderView(initialURL: url,
                           library: site == .simp ? simpLibrary : southLibrary,
                           session: site == .simp ? simpSession : southSession,
                           home: { path = [.home(site)] })
              }
            }
            .environmentObject(site == .simp ? simpLibrary : southLibrary)
            .environmentObject(site == .simp ? simpSession : southSession)
          }
      }.tint(.blue)
        .background { GofileDownloadSurfaces(manager: gofileDownloads) }
        .overlay(alignment: .trailing) {
          FloatingDownloads(manager: downloads, gofile: gofileDownloads, hosted: hostedDownloads)
        }
        .sheet(isPresented: $downloads.showingManager) { DownloadsView(manager: downloads, gofile: gofileDownloads, hosted: hostedDownloads) }
        .onChange(of: scenePhase) { _, value in
          if value == .background { downloads.backgrounded(); gofileDownloads.backgrounded(); hostedDownloads.pauseAll() }
          else if value == .active { downloads.foregrounded() }
        }
        .font(.forum(.body))
    }
  }
}

enum ForumDestination: Hashable {
  case home(ForumSite)
  case search(ForumSite)
  case reader(URL)
  var site: ForumSite {
    switch self {
    case .home(let site), .search(let site): return site
    case .reader(let url): return ForumSite(url: url) ?? .simp
    }
  }
}

struct ForumLogo: View {
  let site: ForumSite
  var body: some View {
    Image(site == .simp ? "ForumLogo" : "SouthLogo")
      .resizable().scaledToFit().padding(site == .simp ? 10 : 6)
      .frame(maxWidth: .infinity).frame(height: 102)
      .background(site == .simp ? Color(white: 0.11) : Color.white, in: RoundedRectangle(cornerRadius: 13))
      .accessibilityHidden(true)
  }
}

struct ForumSelectionView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        ForEach(ForumSite.allCases) { site in
          NavigationLink(value: ForumDestination.home(site)) {
            VStack(spacing: 17) {
              ForumLogo(site: site)
              Text(site.host).font(.forum(.caption)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 23).padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: 182)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 27))
            .overlay(RoundedRectangle(cornerRadius: 27).strokeBorder(Color.primary.opacity(0.04)))
            .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
          }.buttonStyle(.plain).accessibilityLabel("Open \(site.host) home")
        }
      }.frame(maxWidth: 520).padding(.horizontal, 22).padding(.top, 53).padding(.bottom, 40)
        .frame(maxWidth: .infinity)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .toolbar(.hidden, for: .navigationBar)
  }
}

@MainActor
final class LibraryStore: ObservableObject {
  let site: ForumSite
  @Published private(set) var document: LibraryDocument
  @Published var error: String?
  @Published private(set) var refreshing = false
  @Published private(set) var refreshMessage: String?
  @Published private(set) var refreshingAuthors: Set<String> = []
  @Published private(set) var authorErrors: [String: String] = [:]
  private var ready = false
  private var visitTokens: [String: UUID] = [:]
  private var visitTasks: [String: Task<Void, Never>] = [:]
  private var directoryEntries: [ForumEntry] = []
  private var authorTasks: [String: Task<ReaderFailure?, Never>] = [:]
  private var authorTokens: [String: UUID] = [:]
  init(site: ForumSite) { self.site = site; document = LibraryDocument(site: site); reload() }
  func reload() {
    do { document = try LibraryDocument.load(from: .standard, site: site); ready = true; error = nil }
    catch { self.error = error.localizedDescription; ready = false }
  }
  func change(_ mutate: (inout LibraryDocument) -> Void) {
    guard ready else { error = ReaderFailure.storage.localizedDescription; return }
    var next = document
    mutate(&next)
    next.pruneTracking()
    do { try next.save(to: .standard); document = next }
    catch { self.error = "Could not save your reading library." }
  }
  func remember(_ page: ForumPage, session: ForumSession, checkMaximum: Bool = true) {
    guard session.site == site, site.accepts(page.url) else { return }
    if page.kind != .posts { directoryEntries = Array(page.entries.prefix(200)) }
    change {
      $0.remember(SavedPage(url: page.url, title: page.title))
      $0.capturePresentation(page)
      if let key = SitePolicy.threadKey(page.url),
         let entry = directoryEntries.first(where: { SitePolicy.threadKey($0.url) == key }) {
        $0.mergePresentation(ThreadPresentation(thumbnail: entry.thumbnail, tags: page.tags.isEmpty ? entry.tags : [],
                                                authorID: entry.authorID, authorName: entry.authorName), for: page.url)
      }
    }
    guard checkMaximum, ready, page.kind == .posts, let key = SitePolicy.threadKey(page.url) else { return }
    visitTasks[key]?.cancel()
    let token = UUID()
    visitTokens[key] = token
    visitTasks[key] = Task { [weak self] in
      do {
        let maximum = try await session.maximumPostNumber(from: page)
        guard let self, !Task.isCancelled, self.visitTokens[key] == token else { return }
        self.change { $0.threads[key, default: ThreadReadState()].opened(maximum: maximum) }
        self.visitTasks[key] = nil
      } catch {
        guard let self, self.visitTokens[key] == token else { return }
        self.visitTasks[key] = nil
        if !Task.isCancelled { self.refreshMessage = "Could not record this thread's latest post number. Reopen it to try again." }
      }
    }
  }
  func refresh(session: ForumSession) async {
    guard session.site == site, ready, !refreshing else { return }
    let targets = document.trackedThreads
    guard document.hasRefreshTargets else { refreshMessage = nil; return }
    refreshing = true
    defer { refreshing = false }
    var checked = 0
    var failed = 0
    for (index, url) in targets.enumerated() {
      if Task.isCancelled { refreshMessage = "Refresh paused. Existing records are kept."; return }
      guard let key = SitePolicy.threadKey(url) else { continue }
      if let visit = visitTasks[key] { await visit.value }
      if Task.isCancelled { refreshMessage = "Refresh paused. Existing records are kept."; return }
      guard visitTasks[key] == nil else { continue }
      let token = visitTokens[key]
      refreshMessage = "Checking \(index + 1) of \(targets.count)..."
      do {
        let page = try await session.load(url)
        guard !Task.isCancelled else { return }
        change { $0.capturePresentation(page) }
        let maximum = try await session.maximumPostNumber(from: page)
        guard !Task.isCancelled else { refreshMessage = "Refresh paused. Existing records are kept."; return }
        // An in-flight refresh must not overwrite a newer visit or mark a thread read.
        guard visitTokens[key] == token, visitTasks[key] == nil else { continue }
        change { $0.threads[key, default: ThreadReadState()].checked(maximum: maximum) }
        checked += 1
      } catch {
        if Task.isCancelled { refreshMessage = "Refresh paused. Existing records are kept."; return }
        if let failure = error as? ReaderFailure, [.login, .verification, .rateLimit].contains(failure) {
          refreshMessage = failure.localizedDescription + " Existing records are kept."
          return
        }
        failed += 1
      }
    }
    var authorsChecked = 0
    for author in document.following {
      if Task.isCancelled { refreshMessage = "Refresh paused. Existing records are kept."; return }
      refreshMessage = "Checking topics by \(author.name)..."
      if let failure = await refreshAuthor(author.id, session: session) {
        failed += 1
        if [.login, .verification, .rateLimit].contains(failure) {
          refreshMessage = failure.localizedDescription + " Existing records are kept."
          return
        }
      } else { authorsChecked += 1 }
    }
    let summary = authorsChecked == 0 ? "Checked \(checked) threads." : "Checked \(checked) threads and \(authorsChecked) followed authors."
    refreshMessage = failed == 0 ? summary : summary + " \(failed) could not be checked; previous records are kept."
  }
  func follow(_ post: ForumPost, session: ForumSession) {
    guard session.site == site, site == .south, let id = post.authorID else { return }
    change { $0.followAuthor(id: id, name: post.author, avatar: post.avatar) }
    guard document.followsAuthor(id) else { return }
    Task { await refreshAuthor(id, session: session) }
  }
  func unfollow(_ id: String) {
    change { $0.unfollowAuthor(id) }
    guard !document.followsAuthor(id) else { return }
    authorTokens.removeValue(forKey: id)
    authorTasks.removeValue(forKey: id)?.cancel()
    refreshingAuthors.remove(id)
    authorErrors.removeValue(forKey: id)
  }
  @discardableResult
  func refreshAuthor(_ id: String, session: ForumSession) async -> ReaderFailure? {
    guard ready, session.site == site, site == .south, let author = document.followedAuthors[id],
          !document.blocksAuthor(id), let url = SouthSitePolicy.authorTopics(id) else { return nil }
    if let task = authorTasks[id] { return await task.value }
    let token = UUID()
    authorTokens[id] = token
    refreshingAuthors.insert(id)
    authorErrors.removeValue(forKey: id)
    let task = Task { [weak self] () -> ReaderFailure? in
      guard let self else { return nil }
      defer {
        if self.authorTokens[id] == token {
          self.authorTokens.removeValue(forKey: id)
          self.authorTasks.removeValue(forKey: id)
          self.refreshingAuthors.remove(id)
        }
      }
      do {
        let page = try await session.load(url)
        guard !Task.isCancelled, self.authorTokens[id] == token,
              self.document.followedAuthors[id]?.followedAt == author.followedAt else { return nil }
        // Repair legacy names once from a post; profile headings may contain account identifiers.
        var authorPage: ForumPage?
        if author.nameFromPost != true,
           let topic = page.entries.first(where: { $0.authorID == id }),
           let topicURL = SitePolicy.threadRoot(topic.url), self.site.accepts(topicURL) {
          authorPage = try? await session.load(topicURL)
        }
        guard !Task.isCancelled, self.authorTokens[id] == token,
              self.document.followedAuthors[id]?.followedAt == author.followedAt else { return nil }
        guard self.ready else { throw ReaderFailure.storage }
        let checkedAt = Date()
        var accepted = false
        self.change {
          accepted = $0.updateFollowing(page, authorID: id, followedAt: author.followedAt, at: checkedAt)
          if accepted, let authorPage { $0.captureFollowingNames(authorPage) }
        }
        guard accepted else { throw ReaderFailure.unsupported }
        guard self.document.followedAuthors[id]?.checkedAt == checkedAt else { throw ReaderFailure.storage }
        return nil
      } catch {
        guard !Task.isCancelled, self.authorTokens[id] == token,
              self.document.followedAuthors[id]?.followedAt == author.followedAt else { return nil }
        let failure = error as? ReaderFailure ?? .network
        self.authorErrors[id] = failure.localizedDescription
        return failure
      }
    }
    authorTasks[id] = task
    return await task.value
  }
  func toggle(_ url: URL, title: String, titleIsCustom: Bool = false) {
    change { $0.toggle(SavedPage(url: url, title: title, titleIsCustom: titleIsCustom)) }
  }
  func contains(_ url: URL) -> Bool { document.bookmarks.contains { $0.url == url } }
  func resolveBookmarkTitle(_ url: URL, session: ForumSession) {
    guard session.site == site, site.accepts(url) else { return }
    Task { [weak self] in
      do {
        let page = try await session.load(url)
        guard let self, !Task.isCancelled, self.contains(url) else { return }
        self.change { $0.capturePresentation(page); $0.synchronizeTitle(page.title, for: page.url) }
      } catch {
        guard let self, self.contains(url) else { return }
        self.refreshMessage = "Bookmark saved. Its title will update after the page can be loaded."
      }
    }
  }
}

struct ReaderDestination: Hashable {
  var url: URL
}

struct HomeView: View {
  @Binding var path: [ForumDestination]
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
  @State private var adding = false
  @State private var clearHistory = false
  @State private var checkedUpdatesOnLaunch = false
  @State private var showingBlockedAuthors = false
  @State private var browserPresentation: ReaderPresentation?
  private var visibleBookmarks: [SavedPage] { library.document.bookmarks.filter { !library.document.hidesSavedPage($0) } }
  private var visibleRecent: [SavedPage] { library.document.recent.filter { !library.document.hidesSavedPage($0) } }
  var body: some View {
      List {
        Section {
          HStack(spacing: 12) {
            Button { path.append(.reader(session.site.start)) } label: {
              ForumLogo(site: session.site)
            }.buttonStyle(.plain).accessibilityLabel("Open forum reader")
            Button {
              session.beginBrowsing()
              browserPresentation = .browser(session.site.start)
            } label: {
              Image(systemName: "safari").font(.title3).frame(width: 44, height: 44)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
              .accessibilityLabel("Open original forum website")
          }.padding(.vertical, 6)
        }
        Section {
          if visibleBookmarks.isEmpty { Text("No bookmarks").foregroundStyle(.secondary) }
          ForEach(visibleBookmarks) { entry in
            savedRow(entry)
              .swipeActions { Button("Remove", role: .destructive) { library.toggle(entry.url, title: entry.title) } }
          }
        } header: {
          HStack {
            Text("Bookmarks")
            Spacer()
            InfoButton(title: "Bookmarks", message: "Use the bookmark button to save a page or add a forum URL.")
          }
        }
        Section {
          if visibleRecent.isEmpty { Text("No recent pages").foregroundStyle(.secondary) }
          ForEach(visibleRecent) { entry in savedRow(entry) }
        } header: {
          HStack { Text("Recent reading"); Spacer(); if !library.document.recent.isEmpty { Button("Clear") { clearHistory = true } } }
        }
        if session.site == .south {
          SouthFollowingSection(library: library, session: session) { path.append(.reader($0)) }
        }
        if let message = library.refreshMessage {
          Section { Text(message).font(.forum(.caption)).foregroundStyle(.secondary) }
        }
      }
      .navigationTitle(session.site.host)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbarRole(.editor)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            path.append(.search(session.site))
          } label: { Image(systemName: "magnifyingglass") }
            .accessibilityLabel("Search forum")
          if session.site == .south {
            Button { showingBlockedAuthors = true } label: { Image(systemName: "person.slash") }
              .accessibilityLabel("Blocked authors")
          }
          Button { adding = true } label: { Image(systemName: "bookmark") }
            .accessibilityLabel("Add bookmark")
        }
      }
      .safeAreaInset(edge: .bottom, alignment: .trailing) {
        Button { Task { await library.refresh(session: session) } } label: {
          Group {
            if library.refreshing { ProgressView() }
            else { Image(systemName: "arrow.clockwise").font(.title3.weight(.semibold)) }
          }.frame(width: 52, height: 52)
        }.buttonStyle(.glass).buttonBorderShape(.circle)
          .disabled(library.refreshing || !library.document.hasRefreshTargets)
          .accessibilityLabel("Refresh thread and author updates")
          .padding(.trailing, 16).padding(.bottom, 8)
      }
      .refreshable { await library.refresh(session: session) }
      .task {
        guard !checkedUpdatesOnLaunch else { return }
        checkedUpdatesOnLaunch = true
        await library.refresh(session: session)
      }
      .sheet(isPresented: $adding) { BookmarkEditor() }
      .sheet(isPresented: $showingBlockedAuthors) { SouthBlockedAuthorsView(library: library) }
      .fullScreenCover(item: $browserPresentation) { item in
        ReaderController(presentation: item, session: session) { captured in
          browserPresentation = nil
          session.endBrowsing()
          guard let captured, let address = captured["url"] as? String, let target = URL(string: address),
                session.site.accepts(target), let html = captured["html"] as? String else { return }
          // Purchase and poll forms need the original HTTP markup, not a sanitized browser capture.
          let needsFreshPage = session.site == .south &&
            (captured["hasPurchases"] as? Bool == true || captured["hasPoll"] as? Bool == true)
          if !needsFreshPage, let parsed = try? ForumParser().parse(html, url: target) {
            session.pages.store(parsed)
            library.remember(parsed, session: session)
          }
          path.append(.reader(target))
        }.ignoresSafeArea()
      }
      .confirmationDialog("Clear recent reading?", isPresented: $clearHistory, titleVisibility: .visible) {
        Button("Clear recent reading", role: .destructive) { library.change { $0.recent = [] } }
      }
      .alert("Reading library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
        Button("Retry") { library.reload() }
        Button("OK", role: .cancel) { library.error = nil }
      } message: { Text(library.error ?? "") }
  }
  private func savedRow(_ entry: SavedPage) -> some View {
    let key = SitePolicy.threadKey(entry.url)
    let presentation = key.flatMap { library.document.presentations[$0] }
    let state = key.flatMap { library.document.threads[$0] }
    return VStack(alignment: .leading, spacing: 6) {
      if let tags = presentation?.tags, !tags.isEmpty {
        ForumTagStrip(tags: tags) { path.append(.reader($0)) }
      }
      Button { path.append(.reader(entry.url)) } label: {
        HStack(spacing: 10) {
          if let thumbnail = presentation?.thumbnail { ForumThumbnail(url: thumbnail) }
          else { Image(systemName: key == nil ? "folder" : "text.bubble").foregroundStyle(.blue) }
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
              Text(entry.title).lineLimit(2).foregroundStyle(.primary)
              if state?.updated == true {
                Text("Updated").font(.forum(.caption2, weight: .semibold)).foregroundStyle(.blue)
                  .padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.12), in: Capsule())
                  .fixedSize()
              }
            }
            if let subtitle = library.document.subtitle(for: entry), !subtitle.isEmpty {
              Text(subtitle).font(.forum(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let state {
              if let seen = state.seenMaximum {
                Text(state.updated ? "#\(seen) → #\(state.latestMaximum ?? seen)" : "Seen #\(seen)")
                  .font(.forum(.caption)).monospacedDigit().foregroundStyle(state.updated ? .blue : .secondary)
              } else if let latest = state.latestMaximum {
                Text("#\(latest)").font(.forum(.caption)).foregroundStyle(.secondary)
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }.padding(.vertical, 3)
  }
}

struct BookmarkEditor: View {
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
  @Environment(\.dismiss) private var dismiss
  @State private var address = ""
  @State private var title = ""
  @State private var error = ""
  var body: some View {
    NavigationStack {
      Form {
        TextField("Forum or thread URL", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        TextField("Title (optional)", text: $title)
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
      }.navigationTitle("Add bookmark").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) { Button("Save") {
            guard let url = SitePolicy.resolve(address, from: library.site.base, internalOnly: true), library.site.accepts(url) else { error = "Enter a supported \(library.site.host) forum or thread URL."; return }
            guard !library.contains(url) else { error = "This URL is already bookmarked."; return }
            let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
            library.toggle(url, title: label.isEmpty ? url.path : label, titleIsCustom: !label.isEmpty)
            if library.error == nil {
              library.resolveBookmarkTitle(url, session: session)
              dismiss()
            }
          }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }.presentationDetents([.medium, .large])
  }
}
