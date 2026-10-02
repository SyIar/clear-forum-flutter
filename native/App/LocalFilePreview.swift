import ForumUI
import QuickLook
import SwiftUI

/// Opens saved media directly; no URL handoff to another installed player.
struct LocalFilePreview: View {
  let file: URL
  @State private var checked = false
  @State private var available = false
  @State private var immersive = false

  var body: some View {
    Group {
      if !checked { ProgressView() }
      else if !available {
        ForumUnavailableView(AppText.text("File unavailable"), forumSymbol: "doc",
          description: Text(AppText.text("This file was moved or is no longer available. Refresh the folder.")))
      } else if file.pathExtension.lowercased() == "zip" {
        LocalArchiveView(file: file)
      } else if [.video, .audio].contains(LocalMediaKind.kind(file)) {
        LocalVideoSurface(file: file, immersive: $immersive).id(file)
          .background(.black).ignoresSafeArea(.container, edges: immersive ? .all : .bottom)
      } else if QLPreviewController.canPreview(file as NSURL) {
        GofileQuickLook(file: file)
      } else {
        ForumUnavailableView(AppText.text("Preview unavailable"), forumSymbol: "doc",
          description: Text(AppText.text("This file format cannot be previewed here. You can share or export the file.")))
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
      .appFont(.body).navigationTitle(file.lastPathComponent).navigationBarTitleDisplayMode(.inline)
      .statusBarHidden(immersive)
      .toolbarRole(.editor).toolbar(immersive ? .hidden : .visible, for: .navigationBar).toolbar(.hidden, for: .bottomBar)
      .toolbar {
        if available {
          ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: file) { Image(forumSymbol: "square.and.arrow.up") }.accessibilityLabel(AppText.text("Share"))
          }
        }
      }
      .task(id: file) {
        available = file.isFileURL && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        checked = true
      }
  }
}

private struct LocalVideoSurface: UIViewControllerRepresentable {
  let file: URL
  @Binding var immersive: Bool
  func makeUIViewController(context: Context) -> LocalGalleryVideoController {
    let controller = LocalGalleryVideoController(file: file)
    controller.toggleChrome = { immersive.toggle() }
    controller.setActive(true)
    return controller
  }
  func updateUIViewController(_ controller: LocalGalleryVideoController, context: Context) {
    controller.setChromeHidden(immersive)
  }
  static func dismantleUIViewController(_ controller: LocalGalleryVideoController, coordinator: ()) {
    controller.setActive(false)
  }
}
