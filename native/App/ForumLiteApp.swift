import ForumUI
import SwiftUI
import TiebaFeature

@main
struct ForumLiteApp: App {
  @UIApplicationDelegateAdaptor(FileBackgroundDelegate.self) private var backgroundDelegate
  init() { ForumDesignSystem.configure(localize: AppText.text) }
  @StateObject private var wallpaper = DailyWallpaperStore()
  @StateObject private var downloads = VideoDownloadManager.shared
  @StateObject private var gofileDownloads = GofileDownloadManager.shared
  @StateObject private var hostedDownloads = HostedDownloadManager.shared
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var simpLibrary = LibraryStore(site: .simp)
  @StateObject private var southLibrary = LibraryStore(site: .south)
  @StateObject private var bookhouseLibrary = LibraryStore(site: .bookhouse)
  @StateObject private var simpSession = ForumSession(site: .simp)
  @StateObject private var southSession = ForumSession(site: .south)
  @StateObject private var bookhouseSession = ForumSession(site: .bookhouse)
  @StateObject private var tieba = TiebaModuleSession()
  @State private var showingTieba = false
  @State private var showingDownloader = false
  @State private var path: [ForumDestination] = []
  var body: some Scene {
    WindowGroup {
      ModuleNavigationHost(isPresented: $showingTieba, canReturn: { tieba.canReturnToForums },
        root: forumNavigation.environment(\.locale, AppText.locale),
        module: TiebaModuleView(session: tieba) { showingTieba = false }.environment(\.locale, AppText.locale))
        .ignoresSafeArea()
        .background { ForumPresentationHost().frame(width: 0, height: 0) }
        .environment(\.locale, AppText.locale)
        .background { GofileDownloadSurfaces(manager: gofileDownloads) }
        .overlay(alignment: .trailing) {
          FloatingDownloads(manager: downloads, gofile: gofileDownloads, hosted: hostedDownloads)
        }
        .forumSheet(isPresented: $downloads.showingManager) { DownloadsView(manager: downloads, gofile: gofileDownloads, hosted: hostedDownloads) }
        .onChange(of: scenePhase, initial: true) { _, value in
          if value == .background { downloads.backgrounded(); gofileDownloads.backgrounded(); hostedDownloads.backgrounded(); BookhouseOfflineStore.shared.pause(); SouthOfflineStore.shared.pause() }
          else if value == .active {
            downloads.foregrounded(); gofileDownloads.foregrounded(); hostedDownloads.foregrounded()
            if path.contains(where: { $0.site == .south }) { Task { await SouthOfflineStore.shared.resume(session: southSession) } }
          }
        }
    }
  }
  private var forumNavigation: some View {
      NavigationStack(path: $path) {
        ForumSelectionView(openTieba: { showingTieba = true }, openDownloader: { showingDownloader = true })
          .navigationDestination(isPresented: $showingDownloader) { DownloaderView() }
          .navigationDestination(for: ForumDestination.self) { destination in
            let site = destination.site
            Group {
              switch destination {
              case .home:
                HomeView(path: $path)
              case .search:
                ForumSearchView { path.append(.reader($0)) }
              case .book(let id):
                if let book = bookhouseLibrary.document.followedBooks[id] {
                  bookReader(book.resumeURL, id: id)
                }
              case .cachedBook(let match):
                if bookhouseLibrary.document.followedBooks[match.bookID] != nil {
                  bookReader(match.url, id: match.bookID, match: match)
                }
              case .cachedSouth(let url):
                SouthOfflineReader(url: url, library: southLibrary, home: { path = [.home(.south)] })
              case .reader(let url):
                if site == .bookhouse {
                  bookReader(url, id: bookhouseLibrary.document.followedBook(at: url)?.id)
                } else {
                  ReaderView(initialURL: url, library: library(for: site), session: session(for: site), home: { path = [.home(site)] })
                }
              }
            }
            .environmentObject(library(for: site))
            .environmentObject(session(for: site))
          }
      }.tint(.blue)
        .environmentObject(wallpaper)
        .appFont(.body)
  }
  private func library(for site: ForumSite) -> LibraryStore {
    site == .bookhouse ? bookhouseLibrary : site == .simp ? simpLibrary : southLibrary
  }
  private func session(for site: ForumSite) -> ForumSession {
    site == .bookhouse ? bookhouseSession : site == .simp ? simpSession : southSession
  }
  private func bookReader(_ url: URL, id: String?, match: BookhouseOfflineMatch? = nil) -> some View {
    BookhouseReaderView(initialURL: url, navigate: { path.append(.reader($0)) },
      home: { path = [.home(.bookhouse)] }, search: { path.append(.search(.bookhouse)) }, followedBookID: id,
      initialCachedMatch: match, openCachedBook: { path.append(.cachedBook($0)) })
  }
}

enum ForumDestination: Hashable {
  case home(ForumSite)
  case search(ForumSite)
  case reader(URL)
  case book(String)
  case cachedBook(BookhouseOfflineMatch)
  case cachedSouth(URL)
  var site: ForumSite {
    switch self {
    case .home(let site), .search(let site): return site
    case .reader(let url): return ForumSite(url: url) ?? .simp
    case .book, .cachedBook: return .bookhouse
    case .cachedSouth: return .south
    }
  }
}

struct ForumLogo: View {
  let site: ForumSite
  var body: some View {
    Image(site == .bookhouse ? "BookhouseLogo" : site == .simp ? "ForumLogo" : "SouthLogo")
      .resizable().scaledToFit().padding(site == .simp ? 10 : 6)
      .frame(maxWidth: .infinity).frame(height: 102)
      .background(site == .bookhouse ? Color(red: 0.99, green: 0.98, blue: 0.94) : site == .simp ? Color(white: 0.11) : Color.white, in: RoundedRectangle(cornerRadius: 13))
      .accessibilityHidden(true)
  }
}

@MainActor
final class LibraryStore: ObservableObject {
  let site: ForumSite
  @Published private(set) var document: LibraryDocument
  @Published var error: String?
  @Published private(set) var refreshing = false
  @Published private(set) var refreshMessage: String?
  @Published private(set) var threadRefreshPhases: [String: ForumRefreshPhase] = [:]
  @Published private(set) var authorRefreshPhases: [String: ForumRefreshPhase] = [:]
  @Published private(set) var authorErrors: [String: String] = [:]
  var refreshingAuthors: Set<String> { Set(authorRefreshPhases.filter { $0.value == .checking }.keys) }
  private var ready = false
  private var visitTokens: [String: UUID] = [:]
  private var visitTasks: [String: Task<Void, Never>] = [:]
  private var directoryEntries: [ForumEntry] = []
  private var authorTasks: [String: Task<ReaderFailure?, Never>] = [:]
  private var authorTokens: [String: UUID] = [:]
  @Published var bookRefreshPhases: [String: ForumRefreshPhase] = [:]
  @Published var bookErrors: [String: String] = [:]
  @Published var checkProgress = LibraryCheckProgress()
  @Published var onlyUpdates = false
  var bookTasks: [String: Task<Void, Never>] = [:]
  init(site: ForumSite) { self.site = site; document = LibraryDocument(site: site); reload() }
  func reload() {
    do { document = try LibraryDocument.load(from: .standard, site: site); ready = true; error = nil }
    catch { self.error = AppText.error(error); ready = false }
  }
  func change(_ mutate: (inout LibraryDocument) -> Void) {
    guard ready else { error = ReaderFailure.storage.localizedDescription; return }
    var next = document
    mutate(&next)
    next.pruneTracking()
    do { try next.save(to: .standard); document = next }
    catch { self.error = AppText.text("Could not save your reading library.") }
  }
  func remember(_ page: ForumPage, session: ForumSession, checkMaximum: Bool = true) {
    guard session.site == site, site.accepts(page.url) else { return }
    if session.offlineThreadID != nil {
      change { $0.remember(SavedPage(url: page.url, title: page.title)) }
      return
    }
    if page.kind != .posts { directoryEntries = Array(page.entries.prefix(200)) }
    change {
      $0.remember(SavedPage(url: page.url, title: page.title))
      $0.capturePresentation(page)
      $0.recordLatestPage(page)
      if let key = SitePolicy.threadKey(page.url),
         let entry = directoryEntries.first(where: { SitePolicy.threadKey($0.url) == key }) {
        $0.mergePresentation(ThreadPresentation(thumbnail: entry.thumbnail, tags: page.tags.isEmpty ? entry.tags : [],
                                                authorID: entry.authorID, authorName: entry.authorName), for: page.url)
      }
    }
    guard site.supportsThreadUpdates, checkMaximum, ready, page.kind == .posts, let key = SitePolicy.threadKey(page.url) else { return }
    let state = document.threads[key]
    if !LibraryRefreshPolicy.isDue(checkedAt: state?.checkedAt, attemptedAt: state?.attemptedAt, manual: false) {
      if let maximum = state?.latestMaximum {
        // Opening a cached update marks that snapshot read without extending its freshness.
        change { $0.threads[key, default: ThreadReadState()].seenMaximum = maximum }
      }
      return
    }
    change { $0.threads[key, default: ThreadReadState()].attemptedAt = Date() }
    visitTasks[key]?.cancel()
    let token = UUID()
    visitTokens[key] = token
    visitTasks[key] = Task { [weak self] in
      do {
        let latest = try await session.latestThreadPage(from: page)
        guard let maximum = latest.maximumPostNumber else { throw ReaderFailure.unsupported }
        guard let self, !Task.isCancelled, self.visitTokens[key] == token else { return }
        self.change {
          $0.recordLatestPage(latest)
          $0.threads[key, default: ThreadReadState()].opened(maximum: maximum)
        }
        self.threadRefreshPhases[key] = .checked
        self.visitTasks[key] = nil
      } catch {
        guard let self, self.visitTokens[key] == token else { return }
        self.visitTasks[key] = nil
        if !Task.isCancelled { self.refreshMessage = AppText.text("Could not record this thread's latest post number. Reopen it to try again.") }
      }
    }
  }
  func recordVisiblePosts(_ ids: Set<String>, in page: ForumPage) {
    guard ready else { return }
    var next = document
    guard next.recordVisiblePosts(ids, in: page) else { return }
    change { $0 = next }
  }
  func refresh(session: ForumSession, manual: Bool = true) async {
    if site == .bookhouse {
      guard ready else { return }
      await refreshBooks(session: session, manual: manual)
      return
    }
    guard site.supportsThreadUpdates, session.site == site, ready, !refreshing else { return }
    let targets = document.trackedThreads.filter { url in
      guard let key = SitePolicy.threadKey(url) else { return false }
      let state = document.threads[key]
      return LibraryRefreshPolicy.isDue(checkedAt: state?.checkedAt, attemptedAt: state?.attemptedAt, manual: manual)
    }
    let authors = document.following.filter {
      LibraryRefreshPolicy.isDue(checkedAt: $0.checkedAt, attemptedAt: $0.attemptedAt, manual: manual)
    }
    guard document.hasRefreshTargets else { refreshMessage = nil; return }
    guard !targets.isEmpty || !authors.isEmpty else { refreshMessage = nil; if manual { checkProgress = LibraryCheckProgress(skippedFresh: true) }; return }
    refreshing = true
    checkProgress = LibraryCheckProgress(running: true, total: targets.count + authors.count)
    defer { refreshing = false; checkProgress.running = false; checkProgress.currentTitle = nil; checkProgress.finishedAt = Date() }
    var checked = 0
    var failed = 0
    for (index, url) in targets.enumerated() {
      defer { checkProgress.completed += 1 }
      if Task.isCancelled { refreshMessage = AppText.text("Refresh paused. Existing records are kept."); return }
      guard let key = SitePolicy.threadKey(url) else { continue }
      if let visit = visitTasks[key] { await visit.value }
      if Task.isCancelled { refreshMessage = AppText.text("Refresh paused. Existing records are kept."); return }
      guard visitTasks[key] == nil else { continue }
      let state = document.threads[key]
      guard LibraryRefreshPolicy.isDue(checkedAt: state?.checkedAt, attemptedAt: state?.attemptedAt, manual: manual) else { continue }
      change { $0.threads[key, default: ThreadReadState()].attemptedAt = Date() }
      threadRefreshPhases[key] = .checking
      checkProgress.currentTitle = (document.bookmarks + document.recent).first { SitePolicy.threadKey($0.url) == key }?.title
      defer { if threadRefreshPhases[key] == .checking { threadRefreshPhases.removeValue(forKey: key) } }
      let token = visitTokens[key]
      let previousMaximum = document.threads[key]?.latestMaximum ?? document.threads[key]?.seenMaximum
      refreshMessage = AppText.format("Checking %@ of %@...", String(describing: index + 1), String(describing: targets.count))
      do {
        let page = try await session.load(url)
        guard !Task.isCancelled else { return }
        change { $0.capturePresentation(page); $0.recordLatestPage(page) }
        let latest = try await session.latestThreadPage(from: page)
        guard let maximum = latest.maximumPostNumber else { throw ReaderFailure.unsupported }
        guard !Task.isCancelled else { refreshMessage = AppText.text("Refresh paused. Existing records are kept."); return }
        // An in-flight refresh must not overwrite a newer visit or mark a thread read.
        guard visitTokens[key] == token, visitTasks[key] == nil else { continue }
        let checkedAt = Date()
        change {
          $0.recordLatestPage(latest)
          $0.threads[key, default: ThreadReadState()].checked(maximum: maximum, at: checkedAt)
        }
        guard document.threads[key]?.checkedAt == checkedAt else { throw ReaderFailure.storage }
        threadRefreshPhases[key] = previousMaximum.map { maximum > $0 } == true ? .updated : .checked
        if threadRefreshPhases[key] == .updated { checkProgress.updated += 1 }
        checked += 1
      } catch {
        if Task.isCancelled { refreshMessage = AppText.text("Refresh paused. Existing records are kept."); return }
        threadRefreshPhases[key] = .failed
        checkProgress.failed += 1
        if let failure = error as? ReaderFailure, [.login, .verification, .rateLimit].contains(failure) {
          refreshMessage = failure.localizedDescription + AppText.text(" Existing records are kept.")
          return
        }
        failed += 1
      }
    }
    var authorsChecked = 0
    for author in authors {
      defer { checkProgress.completed += 1 }
      if Task.isCancelled { refreshMessage = AppText.text("Refresh paused. Existing records are kept."); return }
      refreshMessage = AppText.format("Checking topics by %@...", String(describing: author.name))
      checkProgress.currentTitle = author.name
      if let failure = await refreshAuthor(author.id, session: session, manual: manual) {
        checkProgress.failed += 1
        failed += 1
        if [.login, .verification, .rateLimit].contains(failure) {
          refreshMessage = failure.localizedDescription + AppText.text(" Existing records are kept.")
          return
        }
      } else { authorsChecked += 1; if authorRefreshPhases[author.id] == .updated { checkProgress.updated += 1 } }
    }
    let summary = authorsChecked == 0 ? AppText.format("Checked %@ threads.", String(describing: checked)) : AppText.format("Checked %@ threads and %@ followed authors.", String(describing: checked), String(describing: authorsChecked))
    refreshMessage = failed == 0 ? nil : summary + AppText.format(" %@ could not be checked; previous records are kept.", String(describing: failed))
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
    authorRefreshPhases.removeValue(forKey: id)
    authorErrors.removeValue(forKey: id)
  }
  @discardableResult
  func refreshAuthor(_ id: String, session: ForumSession, manual: Bool = true) async -> ReaderFailure? {
    guard ready, session.site == site, site == .south, let author = document.followedAuthors[id],
          !document.blocksAuthor(id), let url = SouthSitePolicy.authorTopics(id) else { return nil }
    if let task = authorTasks[id] { return await task.value }
    guard LibraryRefreshPolicy.isDue(checkedAt: author.checkedAt, attemptedAt: author.attemptedAt, manual: manual) else { return nil }
    change { $0.followedAuthors[id]?.attemptedAt = Date() }
    let token = UUID()
    authorTokens[id] = token
    authorRefreshPhases[id] = .checking
    authorErrors.removeValue(forKey: id)
    let task = Task { [weak self] () -> ReaderFailure? in
      guard let self else { return nil }
      defer {
        if self.authorTokens[id] == token {
          self.authorTokens.removeValue(forKey: id)
          self.authorTasks.removeValue(forKey: id)
          if self.authorRefreshPhases[id] == .checking { self.authorRefreshPhases.removeValue(forKey: id) }
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
        let previousTopics = Set(author.topics.compactMap { SitePolicy.threadKey($0.url) })
        let hasNewTopics = self.document.followedAuthors[id]?.topics.contains { topic in
          guard let key = SitePolicy.threadKey(topic.url) else { return false }
          return !previousTopics.contains(key) && self.document.isUnreadSouthThread(topic.url)
        } == true
        self.authorRefreshPhases[id] = hasNewTopics ? .updated : .checked
        return nil
      } catch {
        guard !Task.isCancelled, self.authorTokens[id] == token,
              self.document.followedAuthors[id]?.followedAt == author.followedAt else { return nil }
        let failure = error as? ReaderFailure ?? .network
        self.authorRefreshPhases[id] = .failed
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
  func contains(_ url: URL) -> Bool { document.containsBookmark(url) }
  func resolveBookmarkTitle(_ url: URL, session: ForumSession) {
    guard session.site == site, site.accepts(url) else { return }
    Task { [weak self] in
      do {
        let page = try await session.load(url)
        guard let self, !Task.isCancelled, self.contains(url) else { return }
        self.change { $0.capturePresentation(page); $0.synchronizeTitle(page.title, for: page.url) }
      } catch {
        guard let self, self.contains(url) else { return }
        self.refreshMessage = AppText.text("Bookmark saved. Its title will update after the page can be loaded.")
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
  private var visibleBookmarks: [SavedPage] { library.document.bookmarks.filter { !library.document.hidesSavedPage($0) && (!library.onlyUpdates || hasUpdates($0)) } }
  private var visibleRecent: [SavedPage] { library.document.recent.filter { !library.document.hidesSavedPage($0) && (!library.onlyUpdates || hasUpdates($0)) } }
  var body: some View {
      List {
        Section {
          HStack(spacing: 12) {
            Button { path.append(.reader(session.site.start)) } label: {
              ForumLogo(site: session.site)
            }.buttonStyle(.plain).accessibilityLabel(AppText.text("Open forum reader"))
            Button {
              session.beginBrowsing()
              browserPresentation = .browser(session.site.start)
            } label: {
              Image(forumSymbol: "safari", size: 20).font(.title3).frame(width: 44, height: 44)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
              .accessibilityLabel(AppText.text("Open original forum website"))
          }.padding(.vertical, 6)
        }
        if session.site == .bookhouse {
          BookhouseFollowingSection(library: library, session: session) { path.append(.book($0)) }
        }
        if session.site == .south {
          SouthDownloadsSection(session: session, library: library) { path.append(.cachedSouth($0)) }
        }
        if session.site != .bookhouse {
        Section {
          if visibleBookmarks.isEmpty { Text(AppText.text("No bookmarks")).foregroundStyle(.secondary) }
          ForEach(visibleBookmarks) { entry in
            savedRow(entry, isBookmark: true)
              .swipeActions { Button(AppText.text("Remove"), role: .destructive) { library.toggle(entry.url, title: entry.title) } }
          }
        } header: {
          HStack {
            Text(AppText.text("Bookmarks"))
            Spacer()
            InfoButton(title: AppText.text("Bookmarks"), message: AppText.text("Use the bookmark button to save a page or add a forum URL."))
          }
        }
        }
        Section {
          if visibleRecent.isEmpty { Text(AppText.text("No recent pages")).foregroundStyle(.secondary) }
          ForEach(visibleRecent) { entry in savedRow(entry) }
        } header: {
          HStack { Text(AppText.text("Recent reading")); Spacer(); if !library.document.recent.isEmpty { Button(AppText.text("Clear")) { clearHistory = true } } }
        }
        if session.site == .south {
          SouthFollowingSection(library: library, session: session) { path.append(.reader($0)) }
        }
      }
      .navigationTitle(session.site == .bookhouse ? AppText.text("Forbidden Library") : session.site.host)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbarRole(.editor)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            path.append(.search(session.site))
          } label: { Image(forumSymbol: "magnifyingglass") }
            .accessibilityLabel(AppText.text("Search forum"))
          if session.site == .south {
            Button { showingBlockedAuthors = true } label: { Image(forumSymbol: "person.slash") }
              .accessibilityLabel(AppText.text("Blocked authors"))
          }
          if session.site != .bookhouse {
            Button { adding = true } label: { Image(forumSymbol: "bookmark") }
              .accessibilityLabel(AppText.text("Add bookmark"))
          }
        }
      }
      .safeAreaInset(edge: .bottom, alignment: .trailing) {
        LibraryUpdateButton(library: library) { Task { await library.refresh(session: session) } }
          .padding(.trailing, 16).padding(.bottom, 8)
      }
      .modifier(LibraryUpdateRefresh(library: library, session: session))
      .task {
        guard session.site.supportsThreadUpdates, !checkedUpdatesOnLaunch else { return }
        checkedUpdatesOnLaunch = true
        await library.refresh(session: session, manual: false)
      }
      .forumSheet(isPresented: $adding) { BookmarkEditor().environmentObject(library).environmentObject(session) }
      .forumSheet(isPresented: $showingBlockedAuthors) { SouthBlockedAuthorsView(library: library) }
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
      .forumConfirmation(AppText.text("Clear recent reading?"), isPresented: $clearHistory, actions: { [
          ForumDialogAction(AppText.text("Clear recent reading"), role: .destructive) { library.change { $0.recent = [] } }
        ] })
      .forumAlert(AppText.text("Reading library"), isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } }), actions: { [
          ForumDialogAction(AppText.text("Retry")) { library.reload() },
          ForumDialogAction(AppText.text("OK"), role: .cancel) { library.error = nil }
        ] }, message: { library.error ?? "" })
  }
  private func hasUpdates(_ entry: SavedPage) -> Bool {
    if session.site == .bookhouse {
      return library.document.readingBooks.contains { book in book.updated && book.chapters.contains { BookhouseSitePolicy.threadKey($0.url) == BookhouseSitePolicy.threadKey(entry.url) } }
    }
    return SitePolicy.threadKey(entry.url).flatMap { library.document.threads[$0]?.updated } == true
  }
  private func savedRow(_ entry: SavedPage, isBookmark: Bool = false) -> some View {
    let destination = isBookmark ? library.document.bookmarkDestination(for: entry) : entry.url
    let key = SitePolicy.threadKey(entry.url)
    let presentation = key.flatMap { library.document.presentations[$0] }
    let state = library.site.supportsThreadUpdates ? key.flatMap { library.document.threads[$0] } : nil
    let refreshPhase = key.flatMap { library.threadRefreshPhases[$0] }
    return VStack(alignment: .leading, spacing: 6) {
      if let tags = presentation?.tags, !tags.isEmpty {
        ForumTagStrip(tags: tags) { path.append(.reader($0)) }
      }
      Button {
        let target = isBookmark ? library.document.bookmarkDestination(for: entry) : entry.url
        path.append(.reader(target))
      } label: {
        HStack(spacing: 10) {
          if session.site == .bookhouse { Image(forumSymbol: "book").foregroundStyle(.blue) }
          else if let thumbnail = presentation?.thumbnail { ForumThumbnail(url: thumbnail) }
          else { Image(forumSymbol: key == nil ? "folder" : "text.bubble").foregroundStyle(.blue) }
          VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
              Text(entry.title).forumFont(.body).lineLimit(2).foregroundStyle(.primary)
              if state?.updated == true {
                Text(AppText.text("Updated")).appFont(.caption2, weight: .semibold).foregroundStyle(.blue)
                  .padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.12), in: Capsule())
                  .fixedSize()
              }
            }
            if let subtitle = library.document.subtitle(for: SavedPage(url: destination, title: entry.title)), !subtitle.isEmpty {
              Text(subtitle).forumFont(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if let state {
              if let seen = state.displayedReadMaximum(for: library.site) {
                Text(library.site != .south && state.updated ? "#\(seen) → #\(state.latestMaximum ?? seen)" : AppText.format("Seen #%@", String(describing: seen)))
                  .appFont(.caption).monospacedDigit().foregroundStyle(state.updated ? .blue : .secondary)
              } else if library.site != .south, let latest = state.latestMaximum {
                Text("#\(latest)").appFont(.caption).foregroundStyle(.secondary)
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          LibraryRefreshIndicator(phase: session.site == .simp ? nil : refreshPhase, showsChevron: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }.padding(.vertical, 3)
      .modifier(ForumRefreshFeedback(phase: refreshPhase))
  }
}

private struct LibraryUpdateRefresh: ViewModifier {
  let library: LibraryStore
  let session: ForumSession
  func body(content: Content) -> some View {
    content.refreshable { await library.refresh(session: session) }
  }
}

struct BookmarkEditor: View {
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  private func dismiss() { if forumDismiss.available { forumDismiss() } else { nativeDismiss() } }
  @State private var address = ""
  @State private var title = ""
  @State private var error = ""
  var body: some View {
    NavigationStack {
      Form {
        TextField(AppText.text("Forum or thread URL"), text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        TextField(AppText.text("Title (optional)"), text: $title)
        if !error.isEmpty { Text(error).foregroundStyle(.red) }
      }.navigationTitle(AppText.text("Add bookmark")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(AppText.text("Cancel")) { dismiss() } }
          ToolbarItem(placement: .confirmationAction) { Button(AppText.text("Save")) {
            guard let url = SitePolicy.resolve(address, from: library.site.base, internalOnly: true), library.site.accepts(url) else { error = AppText.format("Enter a supported %@ forum or thread URL.", String(describing: library.site.host)); return }
            guard !library.contains(url) else { error = AppText.text("This URL is already bookmarked."); return }
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
