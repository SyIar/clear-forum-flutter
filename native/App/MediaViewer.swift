import SwiftUI
import UIKit

struct ImageGalleryEntry: Identifiable, Equatable {
  var id: URL { url }
  let url: URL
  let previewURL: URL
}

struct ImageViewerSource {
  let preview: UIImage
  let url: URL
  var loadOriginalOnOpen = false
  var gallery: [ImageGalleryEntry] = []
}

struct ImageViewerPresentation: Identifiable {
  let id = UUID()
  let source: ImageViewerSource
}

enum MediaViewerItem: Identifiable, Hashable {
  case image(UUID, ImageViewerSource)
  case video(URL, Bool, URL)
  var id: String {
    switch self {
    case .image(let id, _): return id.uuidString
    case .video(let url, let direct, let referer): return "\(referer.host ?? ""):\(direct):\(url.absoluteString)"
    }
  }
  static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor
final class MediaViewerState: ObservableObject {
  @Published var immersive = false
  @Published var downloadReady = false
  let download: VideoDownload?
  weak var player: MediaPlayerController?
  weak var image: OriginalImageController?
  init(item: MediaViewerItem) {
    if case .video(let url, _, _) = item { download = VideoDownload.existingOrNew(for: url) }
    else { download = nil }
  }
}

// Media is a destination in the reader's existing stack. UIKit/SwiftUI owns
// recognition, interactive cancellation, and the horizontal pop animation.
struct MediaViewerDestination: View {
  let item: MediaViewerItem
  @StateObject private var state: MediaViewerState
  init(item: MediaViewerItem) {
    self.item = item
    _state = StateObject(wrappedValue: MediaViewerState(item: item))
  }
  private var isImage: Bool { if case .image = item { return true }; return false }
  private var title: String {
    switch item { case .image: return "Image"; case .video: return "Video" }
  }
  var body: some View {
    MediaViewerContent(item: item, state: state)
      .ignoresSafeArea(.container, edges: state.immersive ? .all : .bottom)
      .background(Color(uiColor: isImage || state.immersive ? .black : .systemBackground))
      .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .toolbarRole(.editor)
      .toolbar(state.immersive ? .hidden : .visible, for: .navigationBar)
      .toolbar(.hidden, for: .bottomBar)
      .toolbarColorScheme(isImage || state.immersive ? .dark : nil, for: .navigationBar)
      .statusBarHidden(state.immersive)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          if isImage {
            Button("Share image", systemImage: "square.and.arrow.up") { state.image?.shareImage() }
          } else if let download = state.download {
            VideoDownloadButton(state: state, download: download)
            Button("Refresh video", systemImage: "arrow.clockwise") { state.player?.reload() }
          }
        }
      }
  }
}

private struct MediaViewerContent: UIViewControllerRepresentable {
  let item: MediaViewerItem
  let state: MediaViewerState
  func makeUIViewController(context: Context) -> UIViewController {
    switch item {
    case .image(_, let source):
      let controller = OriginalImageController(source: source)
      state.image = controller
      return controller
    case .video(let url, let direct, let referer):
      let download = state.download ?? VideoDownload.existingOrNew(for: url)
      let controller = MediaPlayerController(url: url, direct: direct, referer: referer, download: download, completion: {})
      controller.immersiveChanged = { [weak state] value in state?.immersive = value }
      controller.downloadAvailabilityChanged = { [weak state] value in
        if state?.downloadReady != value { state?.downloadReady = value }
      }
      state.player = controller
      return controller
    }
  }
  func updateUIViewController(_ controller: UIViewController, context: Context) {}
  static func dismantleUIViewController(_ controller: UIViewController, coordinator: ()) {
    // A canceled system pop keeps this destination and its player alive.
    (controller as? MediaPlayerController)?.finishPlayback()
    (controller as? OriginalImageController)?.stopLoading()
  }
}

// Forum images use the native resizable sheet, preserving the mounted reader.
// A controller is released on each gallery change, cancelling any original load.
struct ImageViewerSheet: View {
  let source: ImageViewerSource
  @EnvironmentObject private var session: ForumSession
  @Environment(\.dismiss) private var dismiss
  @State private var index: Int
  @State private var loadedSource: ImageViewerSource?
  @State private var detent: PresentationDetent = .large
  @StateObject private var state: MediaViewerState
  init(source: ImageViewerSource) {
    self.source = source
    _index = State(initialValue: source.gallery.firstIndex { $0.url == source.url } ?? 0)
    _loadedSource = State(initialValue: source)
    _state = StateObject(wrappedValue: MediaViewerState(item: .image(UUID(), source)))
  }
  private var entries: [ImageGalleryEntry] {
    source.gallery.isEmpty ? [ImageGalleryEntry(url: source.url, previewURL: source.url)] : source.gallery
  }
  private var selected: ImageGalleryEntry { entries[min(index, entries.count - 1)] }
  var body: some View {
    NavigationStack {
      ZStack {
        if let loadedSource, loadedSource.url == selected.url {
          SheetImageContent(source: loadedSource, state: state).id(selected.url)
        } else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
      }
      .background(.black, in: RoundedRectangle(cornerRadius: 24))
      .clipShape(RoundedRectangle(cornerRadius: 24))
      .overlay {
        if entries.count > 1 {
          HStack {
            galleryButton("Previous image", symbol: "chevron.left", disabled: index == 0) { index -= 1 }
            Spacer()
            galleryButton("Next image", symbol: "chevron.right", disabled: index == entries.count - 1) { index += 1 }
          }.padding(.horizontal, 12)
        }
      }
      .padding(6).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30)).padding(8)
      .navigationTitle(entries.count > 1 ? "Image \(index + 1) of \(entries.count)" : "Image")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Close", systemImage: "xmark") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Share image", systemImage: "square.and.arrow.up") { state.image?.shareImage() }
            .disabled(loadedSource?.url != selected.url)
        }
      }
      .task(id: selected.url) {
        let entry = selected
        if entry.url == source.url { loadedSource = source; return }
        loadedSource = nil
        let preview = await session.images.load(entry.previewURL)
        guard !Task.isCancelled, selected.url == entry.url else { return }
        loadedSource = ImageViewerSource(preview: preview ?? UIImage(), url: entry.url, loadOriginalOnOpen: preview == nil)
      }
    }
    .presentationDetents([.medium, .large], selection: $detent)
    .presentationDragIndicator(.visible)
    .presentationContentInteraction(.resizes)
  }
  private func galleryButton(_ title: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) { Image(systemName: symbol).font(.title3.weight(.semibold)).frame(width: 44, height: 44) }
      .buttonStyle(.glass).buttonBorderShape(.circle).disabled(disabled).accessibilityLabel(title)
  }
}

private struct SheetImageContent: UIViewControllerRepresentable {
  let source: ImageViewerSource
  let state: MediaViewerState
  func makeUIViewController(context: Context) -> OriginalImageController {
    let controller = OriginalImageController(source: source)
    state.image = controller
    return controller
  }
  func updateUIViewController(_ controller: OriginalImageController, context: Context) {
    state.image = controller
  }
  static func dismantleUIViewController(_ controller: OriginalImageController, coordinator: ()) { controller.stopLoading() }
}
