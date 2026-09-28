import SwiftUI

@main
struct SimpcityUltimateApp: App {
  @StateObject private var library = LibraryStore()
  @StateObject private var session = ForumSession()
  var body: some Scene {
    WindowGroup {
      HomeView().environmentObject(library).environmentObject(session).tint(.blue)
    }
  }
}

@MainActor
final class LibraryStore: ObservableObject {
  @Published private(set) var document = LibraryDocument()
  @Published var error: String?
  @Published private(set) var refreshing = false
  @Published private(set) var refreshMessage: String?
  private var ready = false
  private var visitTokens: [String: UUID] = [:]
  private var visitTasks: [String: Task<Void, Never>] = [:]
  init() { reload() }
  func reload() {
    do { document = try LibraryDocument.load(from: .standard); ready = true; error = nil }
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
  func remember(_ page: ForumPage, session: ForumSession) {
    change { $0.remember(SavedPage(url: page.url, title: page.title)) }
    guard ready, page.kind == .posts, let key = SitePolicy.threadKey(page.url) else { return }
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
    guard ready, !refreshing else { return }
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
  @EnvironmentObject private var library: LibraryStore
  @EnvironmentObject private var session: ForumSession
  @State private var path: [ReaderDestination] = []
  @State private var adding = false
  @State private var clearHistory = false
  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Text("Pick up where you left off.").font(.title2.bold())
            Text("Your links. Your reading space.").foregroundStyle(.secondary)
            NavigationLink(value: ReaderDestination(url: SitePolicy.base)) { Label("Open forum", systemImage: "globe") }
          }.padding(.vertical, 8)
        }
        Section("Bookmarks") {
          if library.document.bookmarks.isEmpty { Text("Save a page, or add a URL using the bookmark button.").foregroundStyle(.secondary) }
          ForEach(library.document.bookmarks) { entry in
            NavigationLink(value: ReaderDestination(url: entry.url)) { savedRow(entry) }
              .swipeActions { Button("Remove", role: .destructive) { library.toggle(entry.url, title: entry.title) } }
          }
        }
        Section {
          if library.document.recent.isEmpty { Text("Your last 10 visited pages will appear here.").foregroundStyle(.secondary) }
          ForEach(library.document.recent) { entry in NavigationLink(value: ReaderDestination(url: entry.url)) { savedRow(entry) } }
        } header: {
          HStack { Text("Recent reading"); Spacer(); if !library.document.recent.isEmpty { Button("Clear") { clearHistory = true } } }
        }
        if let message = library.refreshMessage {
          Section { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
      }
      .navigationTitle("simp lite")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add bookmark", systemImage: "bookmark.badge.plus") { adding = true } } }
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
      .task(id: path.isEmpty) { if path.isEmpty { await library.refresh(session: session) } }
      .navigationDestination(for: ReaderDestination.self) { destination in ReaderView(initialURL: destination.url, home: { path = [] }) }
      .sheet(isPresented: $adding) { BookmarkEditor() }
      .confirmationDialog("Clear recent reading?", isPresented: $clearHistory, titleVisibility: .visible) {
        Button("Clear recent reading", role: .destructive) { library.change { $0.recent = [] } }
      }
      .alert("Reading library", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
        Button("Retry") { library.reload() }
        Button("OK", role: .cancel) { library.error = nil }
      } message: { Text(library.error ?? "") }
    }
  }
  private func savedRow(_ entry: SavedPage) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top, spacing: 8) {
        Text(entry.title).lineLimit(2)
        if let key = SitePolicy.threadKey(entry.url), library.document.threads[key]?.updated == true {
          Text("Updated").font(.caption2.weight(.semibold)).foregroundStyle(.blue)
            .padding(.horizontal, 7).padding(.vertical, 3).background(.blue.opacity(0.12), in: Capsule())
            .fixedSize()
        }
      }
      Text(entry.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      if let key = SitePolicy.threadKey(entry.url), let state = library.document.threads[key] {
        if let seen = state.seenMaximum {
          Text(state.updated ? "#\(seen) → #\(state.latestMaximum ?? seen)" : "Seen #\(seen)")
            .font(.caption).monospacedDigit().foregroundStyle(state.updated ? .blue : .secondary)
        } else if let latest = state.latestMaximum {
          Text("#\(latest) · Open to start tracking").font(.caption).foregroundStyle(.secondary)
        }
      }
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
            guard let url = SitePolicy.resolve(address, from: SitePolicy.base, internalOnly: true) else { error = "Enter a supported simpcity.cr forum or thread URL."; return }
            guard !library.contains(url) else { error = "This URL is already bookmarked."; return }
            library.toggle(url, title: title.isEmpty ? url.path : title)
            if library.error == nil { dismiss() }
          }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }.presentationDetents([.medium, .large])
  }
}

