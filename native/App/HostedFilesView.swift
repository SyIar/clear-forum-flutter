import SwiftUI

struct HostedFilesDestination: Hashable { let url: URL }

@MainActor
private final class HostedBrowserModel: ObservableObject {
  @Published var listing: HostedFileListing?
  @Published var error: String?
  @Published var retryAfter: Date?
  @Published var loading = false
  private var loadedRevision = -1
  let client = HostedFileClient()
  func load(_ url: URL, revision: Int) async {
    guard !loading, loadedRevision != revision || listing == nil else { return }
    loading = true; error = nil; retryAfter = nil
    defer { loading = false }
    do { listing = try await client.listing(url); loadedRevision = revision }
    catch is CancellationError { }
    catch {
      guard !Task.isCancelled else { return }
      self.error = error.localizedDescription; retryAfter = (error as? HostedFileFailure)?.retryDate
    }
  }
}

struct HostedFilesView: View {
  let url: URL
  @StateObject private var model = HostedBrowserModel()
  @ObservedObject private var downloads = HostedDownloadManager.shared
  @State private var query = ""
  @State private var revision = 0
  @State private var website: URL?
  @State private var batch: HostedBatchDownload?
  @State private var showingBatch = false
  @State private var media: MediaViewerItem?
  @State private var opening: String?
  @State private var playError: String?
  @State private var playTask: Task<Void, Never>?
  private var visible: [HostedFileEntry] {
    let entries = model.listing?.entries ?? []
    return query.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
  var body: some View {
    List {
      if let listing = model.listing {
        Section {
          Text(listing.title).font(.forum(.headline)).textSelection(.enabled)
          if listing.expandedAlbum {
            Label("Showing the complete album", systemImage: "rectangle.stack").font(.forum(.caption)).foregroundStyle(.secondary)
          }
          HStack(spacing: 12) {
            if listing.entries.contains(where: { $0.folder || !TorrentMetadata.isTorrent(name: $0.name, mime: $0.mime) }) {
              Button { enqueue(listing) } label: {
                Text("Download all").font(.forum(.subheadline, weight: .semibold))
                  .lineLimit(1).minimumScaleFactor(0.85).padding(.horizontal, 8)
                  .frame(minHeight: 32, alignment: .center)
              }.buttonStyle(.glassProminent).disabled(model.loading || model.error != nil)
            }
            Spacer(minLength: 0)
            Text(listing.entries.count == 1 ? "1 item" : "\(listing.entries.count) items")
              .font(.forum(.caption)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
          }
        }
      }
      if model.loading { Section { HStack { ProgressView(); Text("Loading files").foregroundStyle(.secondary) } } }
      if let error = model.error {
        Section {
          Label(error, systemImage: "exclamationmark.triangle").font(.forum(.subheadline)).foregroundStyle(.secondary)
          TimelineView(.periodic(from: .now, by: 1)) { context in
            if let date = model.retryAfter, date > context.date {
              Text("Try again in \(Int(ceil(date.timeIntervalSince(context.date))))s").font(.forum(.caption)).monospacedDigit()
            } else { Button("Retry", systemImage: "arrow.clockwise") { revision += 1 }.disabled(model.loading) }
          }
          Button("Open website", systemImage: "safari") { website = url }
        }
      }
      if !visible.isEmpty {
        Section("Files") {
          ForEach(visible) { entry in
            if entry.folder {
              NavigationLink { HostedFilesView(url: entry.pageURL) } label: { fileLabel(entry) }
            } else {
              HStack(spacing: 12) {
                fileLabel(entry)
                Spacer(minLength: 0)
                if TorrentMetadata.isTorrent(name: entry.name, mime: entry.mime) {
                  TorrentCopyButton {
                    try await HostedTransfer.run(entry, client: model.client, limit: Int64(TorrentMetadata.limit), progress: { _ in })
                  }
                } else {
                  if entry.mime.hasPrefix("video/") {
                    Button { play(entry) } label: {
                      ZStack {
                        if opening == entry.id { ProgressView().controlSize(.small) }
                        else { Image(systemName: "play.circle") }
                      }.font(.body.weight(.medium))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless).disabled(opening != nil).accessibilityLabel("Play \(entry.name)")
                  }
                  Button { enqueue(HostedFileListing(url: entry.pageURL, title: entry.name, entries: [entry])) } label: {
                    Image(systemName: "arrow.down.circle").font(.body.weight(.medium))
                      .frame(width: 44, height: 44).contentShape(Rectangle())
                  }.buttonStyle(.borderless).accessibilityLabel("Download \(entry.name)")
                }
              }.contextMenu { Button("Open website", systemImage: "safari") { website = entry.pageURL } }
            }
          }
        }
      } else if model.listing != nil, !model.loading, model.error == nil {
        ContentUnavailableView(query.isEmpty ? "This folder is empty" : "No matching files", systemImage: "folder")
      }
      if downloads.items.contains(where: { $0.sourceKey == HostedFilePolicy.key(model.listing?.url ?? url) }) {
        Section("Downloads") {
          ForEach(downloads.items.filter { $0.sourceKey == HostedFilePolicy.key(model.listing?.url ?? url) }) { HostedBatchRow(batch: $0) }
        }
      }
    }.navigationTitle(HostedFilePolicy.provider(url)?.title ?? "Files").navigationBarTitleDisplayMode(.inline)
      .toolbarRole(.editor).toolbar(.hidden, for: .bottomBar)
      .searchable(text: $query, prompt: "Find a file")
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button("Open website", systemImage: "safari") { website = model.listing?.url ?? url }
          Button("Refresh", systemImage: "arrow.clockwise") { revision += 1 }.disabled(model.loading)
        }
      }
      .task(id: revision) { await model.load(url, revision: revision) }
      .onDisappear { playTask?.cancel(); playTask = nil; opening = nil }
      .navigationDestination(isPresented: $showingBatch) { if let batch { HostedBatchView(batch: batch) } }
      .navigationDestination(item: $media) { MediaViewerDestination(item: $0) }
      .background { ExternalBrowserPresenter(url: $website, useFileBrowser: false).frame(width: 0, height: 0) }
      .alert("Could not open video", isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } })) {
        Button("Open website") { website = url }
        Button("Close", role: .cancel) { playError = nil }
      } message: { Text(playError ?? "") }
  }
  private func fileLabel(_ entry: HostedFileEntry) -> some View {
    HStack(spacing: 12) {
      Image(systemName: entry.symbol).font(.title2).foregroundStyle(.blue)
        .frame(width: 44, height: 44).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.name).font(.forum(.subheadline)).foregroundStyle(.primary).lineLimit(3)
        Text(entry.folder ? "Folder" : entry.sizeDescription).font(.forum(.caption)).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 4)
  }
  private func enqueue(_ listing: HostedFileListing) {
    batch = downloads.enqueue(listing); showingBatch = true
  }
  private func play(_ entry: HostedFileEntry) {
    opening = entry.id
    playTask = Task {
      defer { opening = nil }
      do {
        let request = try await model.client.resolve(entry, download: false)
        try Task.checkCancellation()
        media = .video(request.url, true, request.referer)
      } catch { if !Task.isCancelled { playError = error.localizedDescription } }
    }
  }
}

struct HostedModalRoot: View {
  let url: URL
  var close: () -> Void
  var body: some View {
    NavigationStack {
      HostedFilesView(url: url).toolbar {
        ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.left", action: close) }
      }
    }.font(.forum(.body))
  }
}
