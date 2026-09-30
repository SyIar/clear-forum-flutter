import SwiftUI

// Torrent bytes are temporary metadata only; this never starts a BT download.
struct TorrentCopyButton: View {
  let load: @MainActor () async throws -> URL
  var unavailable = false
  @State private var task: Task<Void, Never>?
  @State private var copied = false
  @State private var error: String?
  var body: some View {
    Button {
      copied = false
      task = Task { @MainActor in
        defer { task = nil }
        do {
          let file = try await load()
          defer { GofileFileTransfer.remove(file) }
          let metadata = try await Task.detached(priority: .userInitiated) {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= TorrentMetadata.limit else { throw TorrentError.invalid }
            return try TorrentMetadata.parse(Data(contentsOf: file))
          }.value
          try Task.checkCancellation()
          UIPasteboard.general.string = metadata.magnet.absoluteString
          copied = true
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      }
    } label: {
      ZStack {
        if task != nil { ProgressView().controlSize(.small) }
        else {
          Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.body.weight(.medium)).contentTransition(.symbolEffect(.replace))
        }
      }.frame(width: 44, height: 44).contentShape(Rectangle())
    }.buttonStyle(.borderless).disabled(task != nil || unavailable)
      .accessibilityLabel(copied ? "Magnet copied" : "Copy magnet")
      .accessibilityValue(task != nil ? "Preparing" : "")
      .onDisappear { task?.cancel(); task = nil }
      .alert("Could not copy magnet", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
        Button("Close", role: .cancel) { error = nil }
      } message: { Text(error ?? "") }
  }
}

@MainActor
enum HostedTransfer {
  static func run(_ entry: HostedFileEntry, client: HostedFileClient, limit: Int64 = GofilePolicy.fileLimit,
                  progress: @escaping (Double?) -> Void) async throws -> URL {
    var active: GofileFileTransfer?
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        let transfer = GofileFileTransfer(name: entry.name, expectedBytes: entry.size, mime: entry.mime, cookies: [],
          userAgent: HostedFileClient.userAgent, limit: limit, prepare: { try await client.resolve(entry) },
          progress: progress, completion: { continuation.resume(with: $0) })
        active = transfer; transfer.start(entry.pageURL)
      }
    } onCancel: { Task { @MainActor in active?.cancel() } }
  }
}
