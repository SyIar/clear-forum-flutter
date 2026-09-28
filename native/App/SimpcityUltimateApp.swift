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
  private var ready = false
  init() { reload() }
  func reload() {
    do { document = try LibraryDocument.load(from: .standard); ready = true; error = nil }
    catch { self.error = error.localizedDescription; ready = false }
  }
  func change(_ mutate: (inout LibraryDocument) -> Void) {
    guard ready else { error = ReaderFailure.storage.localizedDescription; return }
    var next = document
    mutate(&next)
    do { try next.save(to: .standard); document = next }
    catch { self.error = "Could not save your reading library." }
  }
  func remember(_ page: ForumPage) { change { $0.remember(SavedPage(url: page.url, title: page.title)) } }
  func toggle(_ url: URL, title: String) { change { $0.toggle(SavedPage(url: url, title: title)) } }
  func contains(_ url: URL) -> Bool { document.bookmarks.contains { $0.url == url } }
}

struct ReaderDestination: Hashable {
  var url: URL
}

struct HomeView: View {
  @EnvironmentObject private var library: LibraryStore
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
      }
      .navigationTitle("simp lite")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Add bookmark", systemImage: "bookmark.badge.plus") { adding = true } } }
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
      Text(entry.title).lineLimit(2)
      Text(entry.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

