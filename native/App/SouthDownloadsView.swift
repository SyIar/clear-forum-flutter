import ForumUI
import SwiftUI

struct SouthDownloadsSection: View {
  let session: ForumSession
  let library: LibraryStore
  let open: (URL) -> Void
  @ObservedObject private var downloads = SouthOfflineStore.shared
  @State private var showingAll = false
  var body: some View {
    Section {
      if downloads.entries.isEmpty {
        Text(AppText.text("Save a thread from its page actions to read it offline."))
          .appFont(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(Array(downloads.entries.prefix(5))) { entry in
        Button { if entry.savedPages.isEmpty { showingAll = true } else { open(entry.url) } } label: {
          SouthDownloadRow(entry: entry, active: downloads.activeThread == entry.id, progress: downloads.progress)
        }.buttonStyle(.plain)
      }
    } header: {
      Button { showingAll = true } label: {
        HStack {
          Text(AppText.text("Downloaded threads"))
          Spacer()
          Text(AppText.format("View all (%@)", String(downloads.entries.count)))
          Image(forumSymbol: "chevron.right", size: 12)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain)
    }
    .task { await downloads.resume(session: session) }
    .forumSheet(isPresented: $showingAll) { SouthDownloadsView(session: session, library: library) }
  }
}

struct SouthDownloadsView: View {
  let session: ForumSession
  let library: LibraryStore
  @ObservedObject private var downloads = SouthOfflineStore.shared
  @State private var deleting: SouthOfflineThread?
  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(downloads.entries) { entry in
            VStack(alignment: .leading, spacing: 8) {
              if entry.savedPages.isEmpty {
                SouthDownloadRow(entry: entry, active: downloads.activeThread == entry.id, progress: downloads.progress)
              } else {
                NavigationLink {
                  SouthOfflineReader(url: entry.url, library: library, home: {})
                } label: { SouthDownloadRow(entry: entry, active: downloads.activeThread == entry.id, progress: downloads.progress, chevron: false) }
              }
              if entry.state == .failed || entry.state == .partial {
                HStack(alignment: .top) {
                  Text(entry.failure ?? AppText.format("%@ images could not be saved.", String(entry.missingImages)))
                    .appFont(.caption).foregroundStyle(.secondary).lineLimit(3)
                  Spacer(minLength: 8)
                  Button(AppText.text("Continue download")) { downloads.download(url: entry.url, title: entry.title, session: session) }
                    .appFont(.caption).buttonStyle(.bordered).fixedSize()
                }
              }
            }
            .swipeActions { Button(AppText.text("Remove download"), role: .destructive) { deleting = entry } }
            .contextMenu { Button(AppText.text("Remove download"), forumSymbol: "trash", role: .destructive) { deleting = entry } }
          }
        } footer: {
          Text(AppText.text("Saves all readable pages and images. Videos and attachments are downloaded separately. Interrupted downloads resume when South opens."))
        }
      }
      .overlay { if downloads.entries.isEmpty { ForumUnavailableView(AppText.text("No downloaded threads"), forumSymbol: "arrow.down.circle") } }
      .navigationTitle(AppText.text("Downloaded threads")).navigationBarTitleDisplayMode(.inline)
      .forumConfirmation(AppText.text("Remove this offline thread?"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), actions: {
        [ForumDialogAction(AppText.text("Remove download"), role: .destructive) {
          if let entry = deleting { Task { await downloads.remove(entry) } }
          deleting = nil
        }]
      })
      .forumAlert(AppText.text("Downloaded threads"), isPresented: Binding(get: { downloads.error != nil }, set: { if !$0 { downloads.error = nil } }), actions: {
        [ForumDialogAction(AppText.text("OK"), role: .cancel) { downloads.error = nil }]
      }, message: { downloads.error ?? "" })
    }.presentationDetents([.large])
  }
}

private struct SouthDownloadRow: View {
  let entry: SouthOfflineThread
  let active: Bool
  let progress: String
  var chevron = true
  var body: some View {
    HStack(spacing: 10) {
      Image(forumSymbol: "arrow.down.circle", size: 22).foregroundStyle(.blue)
      VStack(alignment: .leading, spacing: 5) {
        Text(entry.title).forumFont(.body).foregroundStyle(.primary).lineLimit(2)
        HStack(spacing: 8) {
          Text(AppText.format("%@/%@ pages", String(entry.savedPages.count), String(entry.totalPages)))
          Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file))
          if entry.state == .pending && !active { Text(AppText.text("Queued")) }
          if entry.state == .complete { Text(AppText.text("Available offline")) }
        }.appFont(.caption).foregroundStyle(.secondary)
        if active { Text(progress).appFont(.caption).foregroundStyle(.blue).lineLimit(1) }
      }.frame(maxWidth: .infinity, alignment: .leading)
      if active { ProgressView().controlSize(.small) }
      else if entry.state == .failed || entry.state == .partial { Image(forumSymbol: "exclamationmark.triangle", size: 16).foregroundStyle(.orange) }
      else if chevron { Image(forumSymbol: "chevron.right", size: 12).foregroundStyle(.tertiary) }
    }.padding(.vertical, 3).contentShape(Rectangle())
  }
}

struct SouthOfflineReader: View {
  let url: URL
  let library: LibraryStore
  let home: () -> Void
  @StateObject private var session: ForumSession
  @Environment(\.dismiss) private var dismiss
  init(url: URL, library: LibraryStore, home: @escaping () -> Void) {
    self.url = url; self.library = library; self.home = home
    _session = StateObject(wrappedValue: ForumSession(site: .south, offlineThreadID: SouthSitePolicy.threadKey(url)))
  }
  var body: some View {
    ReaderView(initialURL: url, library: library, session: session, home: { dismiss(); home() })
  }
}
