import Combine
import ForumUI
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct LocalFilesView: View {
  @StateObject private var store: LocalFilesStore
  @State private var search = ""
  @State private var gallery: LocalGalleryRequest?
  @Environment(\.scenePhase) private var scenePhase

  init(path: [String] = []) { _store = StateObject(wrappedValue: LocalFilesStore(path: path)) }
  private var entries: [LocalFileEntry] {
    store.entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
  }

  var body: some View {
    List {
      if let error = store.error {
        Label(error, forumSymbol: "exclamationmark.triangle").foregroundStyle(.secondary)
      }
      if store.loading && store.entries.isEmpty {
        HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
      } else if entries.isEmpty && store.error == nil {
        ForumUnavailableView(search.isEmpty ? AppText.text("This folder is empty.") : AppText.text("No matching files on this page."),
          forumSymbol: "folder", description: search.isEmpty ? Text(AppText.text("Downloaded files and files copied into Forum Lite appear here.")) : nil)
          .listRowBackground(Color.clear)
      }
      ForEach(entries) { entry in
        if entry.directory {
          NavigationLink { LocalFilesView(path: entry.path) } label: { row(entry) }
        } else {
          Button {
            do {
              guard let catalog = store.catalog else { throw LocalFileCatalog.Failure.unavailable }
              _ = try catalog.url(for: entry.path)
              guard let selection = LocalGallerySelection(entries: store.entries, selected: entry.path) else {
                throw LocalFileCatalog.Failure.unavailable
              }
              gallery = LocalGalleryRequest(catalog: catalog, selection: selection)
            } catch { store.error = AppText.text("This file was moved or is no longer available. Refresh the folder.") }
          } label: { row(entry) }.buttonStyle(.plain)
        }
      }
    }.appFont(.body)
      .navigationTitle(store.path.last ?? AppText.text("Local files"))
      .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
      .toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .bottomBar)
      .searchable(text: $search, prompt: AppText.text("Find files in this folder"))
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(AppText.text("Refresh"), forumSymbol: "arrow.clockwise") { Task { await store.reload() } }
            .disabled(store.loading)
        }
      }
      .task { await store.reload() }
      .refreshable { await store.reload() }
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { Task { await store.reload() } }
      }
      .onReceive(NotificationCenter.default.publisher(for: FileDownloadStore.didInstallFile)
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
          Task { await store.reload() }
        }
      .background { LocalGalleryPresenter(request: $gallery).frame(width: 0, height: 0) }
  }

  private func row(_ entry: LocalFileEntry) -> some View {
    HStack(spacing: 12) {
      LocalFileThumbnail(entry: entry, catalog: store.catalog)
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.name).lineLimit(2).foregroundStyle(.primary)
        HStack(spacing: 8) {
          if let bytes = entry.bytes { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
          if let date = entry.modified { Text(date, format: .dateTime.year().month().day()) }
        }.appFont(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
      if !entry.directory { Image(forumSymbol: "chevron.right", size: 14).foregroundStyle(.tertiary) }
    }.padding(.vertical, 4).contentShape(Rectangle())
  }
}

@MainActor private final class LocalFilesStore: ObservableObject {
  let path: [String]
  private(set) var catalog: LocalFileCatalog?
  @Published private(set) var entries: [LocalFileEntry] = []
  @Published private(set) var loading = true
  @Published var error: String?
  private var revision = UUID()
  init(path: [String]) { self.path = path }

  func reload() async {
    let token = UUID(); revision = token
    loading = true
    defer { if revision == token { loading = false } }
    do {
      let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let catalog = LocalFileCatalog(root: root)
      let path = path
      let task = Task.detached(priority: .userInitiated) { try catalog.entries(in: path) }
      let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
      guard !Task.isCancelled, revision == token else { return }
      self.catalog = catalog
      entries = result; error = nil
    } catch {
      guard !Task.isCancelled, revision == token else { return }
      entries = []
      self.error = AppText.text("Cannot read this folder. It may have been moved or removed in Files.")
    }
  }
}

enum LocalMediaKind: Equatable {
  case image, video, audio, other
  static func kind(_ file: URL) -> LocalMediaKind {
    let ext = file.pathExtension.lowercased()
    let type = UTType(filenameExtension: ext)
    if type?.conforms(to: .image) == true { return .image }
    if type?.conforms(to: .movie) == true || ["mkv", "avi", "webm", "flv", "ts", "m2ts"].contains(ext) { return .video }
    if type?.conforms(to: .audio) == true { return .audio }
    return .other
  }
  var symbol: String {
    switch self { case .image: return "photo"; case .video: return "video"; case .audio: return "audio"; case .other: return "doc" }
  }
}

private struct LocalFileThumbnail: View {
  let entry: LocalFileEntry
  let catalog: LocalFileCatalog?
  @State private var image: UIImage?
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>(); cache.countLimit = 80; cache.totalCostLimit = 16 * 1024 * 1024; return cache
  }()
  private var key: String { "\(entry.path):\(entry.modified?.timeIntervalSince1970 ?? 0):\(entry.bytes ?? 0)" }
  var body: some View {
    Group {
      if let image { Image(uiImage: image).resizable().scaledToFill() }
      else {
        Image(forumSymbol: entry.directory ? "folder" : LocalMediaKind.kind(URL(fileURLWithPath: entry.name)).symbol, size: 24)
          .foregroundStyle(.blue).frame(maxWidth: .infinity, maxHeight: .infinity).background(.blue.opacity(0.08))
      }
    }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
      .accessibilityHidden(true)
      .task(id: key) {
        image = nil
        guard !entry.directory, let catalog, let url = try? catalog.url(for: entry.path),
              [.image, .video].contains(LocalMediaKind.kind(url)) else { return }
        if let cached = Self.cache.object(forKey: key as NSString) { image = cached; return }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 104, height: 104), scale: 1, representationTypes: .thumbnail)
        let result = try? await withTaskCancellationHandler(operation: {
          try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        }, onCancel: { QLThumbnailGenerator.shared.cancel(request) })
        guard !Task.isCancelled, let result else { return }
        let thumbnail = result.uiImage
        Self.cache.setObject(thumbnail, forKey: key as NSString, cost: 104 * 104 * 4)
        image = thumbnail
      }
  }
}
