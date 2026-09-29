import SwiftUI
import UIKit

struct ImageViewerSource {
  let preview: UIImage
  let url: URL
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
    switch item { case .image: return "Image"; case .video(let url, _, _): return url.host ?? "Video" }
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
