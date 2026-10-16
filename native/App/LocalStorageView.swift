import Combine
import ForumUI
import SwiftUI

struct LocalStorageView: View {
  let path: [String]
  @State private var snapshot: LocalStorageSnapshot?
  @State private var catalog: LocalFileCatalog?
  @State private var loading = false
  @State private var error: String?
  @State private var revision = UUID()
  @State private var deletion: LocalFileEntry?
  @State private var preview: GofileLocalFile?

  var body: some View {
    List {
      Section {
        HStack {
          Text(path.last ?? AppText.text("Local files")).lineLimit(2)
          Spacer()
          if loading { ProgressView() }
        }
        if let snapshot {
          Text(ByteCountFormatter.string(fromByteCount: snapshot.bytes, countStyle: .file))
            .appFont(.largeTitle, weight: .semibold).monospacedDigit()
          Text(AppText.format("%@ files, including subfolders", String(snapshot.files.count))).foregroundStyle(.secondary)
          if snapshot.skipped > 0 {
            Text(AppText.format("%@ unavailable items or links were skipped.", String(snapshot.skipped))).appFont(.caption).foregroundStyle(.secondary)
          }
        }
        Text(AppText.text("Total file size in this folder, including subfolders. App caches and Photos are not included."))
          .appFont(.caption).foregroundStyle(.secondary)
        if let error { Text(error).foregroundStyle(.secondary) }
      }
      Section(AppText.text("Largest files first")) {
        ForEach(snapshot?.files ?? []) { file in
          HStack(spacing: 12) {
            Button {
              if let url = try? catalog?.url(for: file.path) { preview = GofileLocalFile(url: url) }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(file.name).foregroundStyle(.primary).lineLimit(2)
                Text(file.path.dropFirst(path.count).dropLast().joined(separator: "/"))
                  .appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: file.bytes ?? 0, countStyle: .file))
                  .appFont(.subheadline, weight: .semibold).foregroundStyle(.blue)
              }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(AppText.text("Delete file"), forumSymbol: "trash", role: .destructive) { deletion = file }
              .labelStyle(.iconOnly).buttonStyle(.borderless).frame(width: 44, height: 44)
          }.padding(.vertical, 3)
            .contextMenu { Button(AppText.text("Delete file"), forumSymbol: "trash", role: .destructive) { deletion = file } }
        }
      }
    }.appFont(.body).navigationTitle(AppText.text("Storage analysis")).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(AppText.text("Refresh"), forumSymbol: "arrow.clockwise") { revision = UUID() }.disabled(loading)
        }
      }
      .task(id: revision) { await load() }
      .onReceive(NotificationCenter.default.publisher(for: FileDownloadStore.didInstallFile)
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in revision = UUID() }
      .modifier(LocalFileDeletion(entry: $deletion, catalog: catalog, completed: { revision = UUID() }))
      .navigationDestination(item: $preview) { LocalFilePreview(file: $0.url) }
  }
  @MainActor private func load() async {
    let token = revision
    loading = true; error = nil
    defer { if token == revision { loading = false } }
    do {
      let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let catalog = LocalFileCatalog(root: root)
      let path = path
      let worker = Task.detached(priority: .utility) { try catalog.storage(in: path) }
      let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
      guard !Task.isCancelled, token == revision else { return }
      self.catalog = catalog; snapshot = result
    } catch {
      guard !Task.isCancelled, token == revision else { return }
      self.error = AppText.text("Cannot read this folder. It may have been moved or removed in Files.")
    }
  }
}
