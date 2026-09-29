import SwiftUI

@main
struct ForumLiteApp: App {
  @StateObject private var simpLibrary = LibraryStore(site: .simp)
  @StateObject private var southLibrary = LibraryStore(site: .south)
  @StateObject private var simpSession = ForumSession(site: .simp)
  @StateObject private var southSession = ForumSession(site: .south)
  @State private var path: [ForumDestination] = []
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
    }
  }
}

enum ForumDestination: Hashable {
  case home(ForumSite)
  case reader(URL)
  var site: ForumSite {
    switch self {
    case .home(let site): return site
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
              Text(site.host).font(.caption).foregroundStyle(.secondary)
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
  private var ready = false
  private var visitTokens: [String: UUID] = [:]
  private var visitTasks: [String: Task<Void, Never>] = [:]
  private var directoryEntries: [ForumEntry] = []
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
        $0.mergePresentation(ThreadPresentation(thumbnail: entry.thumbnail, tags: page.tags.isEmpty ? entry.tags : [], authorID: entry.authorID), for: page.url)
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
    guard !targets.isEmpty else { refreshMessage = nil; return }
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
    refreshMessage = failed == 0 ? "Checked \(checked) threads just now." : "Checked \(checked) threads. \(failed) could not be checked; previous records are kept."
  }
  func toggle(_ url: URL, title: String) { change { $0.toggle(SavedPage(url: url, title: title)) } }
  func contains(_ url: URL) -> Bool { document.bookmarks.contains { $0.url == url } }
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
  private var visibleBookmarks: [SavedPage] { library.document.bookmarks.filter { !library.document.hidesSavedPage($0) } }
  private var visibleRecent: [SavedPage] { library.document.recent.filter { !library.document.hidesSavedPage($0) } }
  var body: some View {
      List {
        Section {
          NavigationLink(value: ForumDestination.reader(session.site.start)) {
            VStack(alignment: .leading, spacing: 12) {
              ForumLogo(site: session.site)
              Text("Open forum").font(.headline)
            }.padding(.vertical, 6)
          }
        }
        Section("Bookmarks") {
          if visibleBookmarks.isEmpty { Text("Save a page, or add a URL using the bookmark button.").foregroundStyle(.secondary) }
          ForEach(visibleBookmarks) { entry in
            savedRow(entry)
              .swipeActions { Button("Remove", role: .destructive) { library.toggle(entry.url, title: entry.title) } }
          }
        }
        Section {
          if visibleRecent.isEmpty { Text("Your last 10 visited pages will appear here.").foregroundStyle(.secondary) }
          ForEach(visibleRecent) { entry in savedRow(entry) }
        } header: {
          HStack { Text("Recent reading"); Spacer(); if !library.document.recent.isEmpty { Button("Clear") { clearHistory = true } } }
        }
        if let message = library.refreshMessage {
          Section { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
      }
      .navigationTitle(session.site.host)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar(.visible, for: .navigationBar)
      .toolbarRole(.editor)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          if session.site == .south { Button("Blocked authors", systemImage: "person.slash") { showingBlockedAuthors = true } }
          Button("Add bookmark", systemImage: "bookmark.badge.plus") { adding = true }
        }
      }
      .safeAreaInset(edge: .bottom, alignment: .trailing) {
        Button { Task { await library.refresh(session: session) } } label: {
          Group {
            if library.refreshing { ProgressView() }
            else { Image(systemName: "arrow.clockwise").font(.title3.weight(.semibold)) }
          }.frame(width: 52, height: 52)
        }.buttonStyle(.glass).buttonBorderShape(.circle)
          .disabled(library.refreshing || library.document.trackedThreads.isEmpty)
          .accessibilityLabel("Refresh thread updates")
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
                Text("Updated").font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                  .padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.12), in: Capsule())
                  .fixedSize()
              }
            }
            Text(entry.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let state {
              if let seen = state.seenMaximum {
                Text(state.updated ? "#\(seen) → #\(state.latestMaximum ?? seen)" : "Seen #\(seen)")
                  .font(.caption).monospacedDigit().foregroundStyle(state.updated ? .blue : .secondary)
              } else if let latest = state.latestMaximum {
                Text("#\(latest) · Open to start tracking").font(.caption).foregroundStyle(.secondary)
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
            library.toggle(url, title: title.isEmpty ? url.path : title)
            if library.error == nil { dismiss() }
          }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }.presentationDetents([.medium, .large])
  }
}

