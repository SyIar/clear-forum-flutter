import ForumUI
import SwiftUI

struct LocalFileDeletion: ViewModifier {
  @Binding var entry: LocalFileEntry?
  let catalog: LocalFileCatalog?
  let completed: () -> Void
  @State private var busy = false
  @State private var error: String?

  func body(content: Content) -> some View {
    content
      .forumAlert(AppText.format("Delete %@?", entry?.name ?? ""),
        isPresented: Binding(get: { entry != nil }, set: { if !$0 { entry = nil } }), actions: {
          guard let selected = entry, let catalog else { return [ForumDialogAction(AppText.text("Cancel"), role: .cancel)] }
          return [ForumDialogAction(AppText.text("Delete permanently"), role: .destructive) {
            remove(selected, catalog: catalog)
          }, ForumDialogAction(AppText.text("Cancel"), role: .cancel)]
        }, message: { AppText.text("This permanently deletes the selected file or folder and its contents from this iPhone.") })
      .forumAlert(AppText.text("Local files"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
        actions: { [ForumDialogAction(AppText.text("OK"), role: .cancel)] }, message: { error ?? "" })
      .overlay { if busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
  }
  @MainActor private func remove(_ selected: LocalFileEntry, catalog: LocalFileCatalog) {
    guard !busy else { return }
    do {
      let target = try catalog.url(for: selected.path)
      let downloads = HostedDownloadManager.shared.unfinished.compactMap(\.directory) + GofileDownloadManager.shared.unfinished.compactMap(\.directory)
      let archives = LocalArchiveManager.shared.activeFiles
      func overlaps(_ other: URL) -> Bool {
        let a = target.standardizedFileURL.resolvingSymlinksInPath().path
        let b = other.standardizedFileURL.resolvingSymlinksInPath().path
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
      }
      guard !downloads.contains(where: overlaps), !archives.contains(where: overlaps) else {
        error = AppText.text("Stop the related download or extraction before deleting this file or folder.")
        return
      }
    } catch {
      self.error = AppText.text("This file changed or is no longer available. Refresh the folder before deleting it.")
      return
    }
    busy = true
    Task {
      defer { busy = false }
      do {
        let worker = Task.detached(priority: .userInitiated) { try catalog.remove(selected) }
        try await worker.value
        completed()
        NotificationCenter.default.post(name: FileDownloadStore.didInstallFile, object: nil)
      } catch {
        self.error = AppText.text("Could not delete this item. It may have changed or be in use. Refresh the folder and try again.")
      }
    }
  }
}
