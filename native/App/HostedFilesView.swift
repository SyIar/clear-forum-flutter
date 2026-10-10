import ForumUI
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
      self.error = AppText.error(error); retryAfter = (error as? HostedFileFailure)?.retryDate
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
  @State private var export: GofileLocalFile?
  private var visible: [HostedFileEntry] {
    let entries = model.listing?.entries ?? []
    return query.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
  var body: some View {
    List {
      if let listing = model.listing {
        Section {
          FileListingHeader(title: listing.title, count: listing.entries.count,
            canDownload: listing.entries.contains { $0.folder || !TorrentMetadata.isTorrent(name: $0.name, mime: $0.mime) },
            disabled: model.loading || model.error != nil, album: listing.expandedAlbum) { enqueue(listing) }
        }
      }
      if model.loading { Section { HStack { ProgressView(); Text(AppText.text("Loading files")).foregroundStyle(.secondary) } } }
      if let error = model.error {
        Section {
          Label(error, forumSymbol: "exclamationmark.triangle").appFont(.subheadline).foregroundStyle(.secondary)
          TimelineView(.periodic(from: .now, by: 1)) { context in
            if let date = model.retryAfter, date > context.date {
              Text(AppText.format("Try again in %@s", String(describing: Int(ceil(date.timeIntervalSince(context.date)))))).appFont(.caption).monospacedDigit()
            } else { Button(AppText.text("Retry"), forumSymbol: "arrow.clockwise") { revision += 1 }.disabled(model.loading) }
          }
          Button(AppText.text("Open website"), forumSymbol: "safari") { website = url }
        }
      }
      if !visible.isEmpty {
        Section(AppText.text("Files")) {
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
                        else { Image(forumSymbol: "play.circle") }
                      }.font(.body.weight(.medium))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.borderless).disabled(opening != nil).accessibilityLabel(AppText.format("Play %@", String(describing: entry.name)))
                  }
                  downloadButton(entry)
                }
              }.contextMenu { Button(AppText.text("Open website"), forumSymbol: "safari") { website = entry.pageURL } }
            }
          }
        }
      } else if model.listing != nil, !model.loading, model.error == nil {
        ForumUnavailableView(query.isEmpty ? AppText.text("This folder is empty") : AppText.text("No matching files"), forumSymbol: "folder")
      }
      if downloads.items.contains(where: { $0.sourceKey == HostedFilePolicy.key(model.listing?.url ?? url) }) {
        Section(AppText.text("Downloads")) {
          ForEach(downloads.items.filter { $0.sourceKey == HostedFilePolicy.key(model.listing?.url ?? url) }) { HostedBatchRow(batch: $0) }
        }
      }
    }.navigationTitle(HostedFilePolicy.provider(url)?.title ?? AppText.text("Files")).navigationBarTitleDisplayMode(.inline)
      .toolbarRole(.editor).toolbar(.hidden, for: .bottomBar)
      .searchable(text: $query, prompt: AppText.text("Find a file"))
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button(AppText.text("Open website"), forumSymbol: "safari") { website = model.listing?.url ?? url }
          Button(AppText.text("Refresh"), forumSymbol: "arrow.clockwise") { revision += 1 }.disabled(model.loading)
        }
      }
      .task(id: revision) { await model.load(url, revision: revision) }
      .onDisappear { playTask?.cancel(); playTask = nil; opening = nil }
      .navigationDestination(isPresented: $showingBatch) { if let batch { HostedBatchView(batch: batch) } }
      .navigationDestination(item: $media) { MediaViewerDestination(item: $0) }
      .sheet(item: $export) { GofileExport(file: $0.url) }
      .background { ExternalBrowserPresenter(url: $website, useFileBrowser: false).frame(width: 0, height: 0) }
      .forumAlert(AppText.text("Could not open video"), isPresented: Binding(get: { playError != nil }, set: { if !$0 { playError = nil } }), actions: { [
          ForumDialogAction(AppText.text("Open website")) { website = url },
          ForumDialogAction(AppText.text("Close"), role: .cancel) { playError = nil }
        ] }, message: { playError ?? "" })
  }
  private func fileLabel(_ entry: HostedFileEntry) -> some View {
    HStack(spacing: 12) {
      Image(forumSymbol: entry.symbol, size: 22).font(.title2).foregroundStyle(ForumDesignSystem.primary)
        .frame(width: 44, height: 44).background(ForumDesignSystem.surface, in: RoundedRectangle(cornerRadius: ForumDesignSystem.radius.base))
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.name).appFont(.subheadline).foregroundStyle(.primary).lineLimit(3)
        Text(entry.folder ? AppText.text("Folder") : entry.sizeDescription).appFont(.caption).foregroundStyle(.secondary)
      }
    }.padding(.vertical, 4)
  }
  private func enqueue(_ listing: HostedFileListing) {
    batch = downloads.enqueue(listing)
  }
  private func downloadButton(_ entry: HostedFileEntry) -> some View {
    let task = downloads.download(for: entry)
    let file = task?.file(for: entry).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    return FileDownloadAction(exists: task != nil, running: task?.running == true && task?.isCurrent(entry) == true,
      completed: file != nil, progress: task?.progress) {
      if let file { export = GofileLocalFile(url: file) }
      else if task != nil { VideoDownloadManager.shared.showingManager = true }
      else { enqueue(HostedFileListing(url: entry.pageURL, title: entry.name, entries: [entry])) }
    }
  }
  private func play(_ entry: HostedFileEntry) {
    opening = entry.id
    playTask = Task {
      defer { opening = nil }
      do {
        let request = try await model.client.resolve(entry, download: false)
        try Task.checkCancellation()
        VideoOrigins.register(request.url, title: entry.name, page: entry.pageURL)
        media = .video(request.url, true, request.referer)
      } catch { if !Task.isCancelled { playError = AppText.error(error) } }
    }
  }
}

struct HostedModalRoot: View {
  let url: URL
  var close: () -> Void
  var body: some View {
    NavigationStack {
      HostedFilesView(url: url).toolbar {
        ToolbarItem(placement: .topBarLeading) { Button(AppText.text("Back"), forumSymbol: "chevron.left", action: close) }
      }
    }.appFont(.body)
      .environment(\.locale, AppText.locale)
  }
}
