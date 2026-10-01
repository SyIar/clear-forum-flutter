import ForumUI
import SwiftUI
import Combine

@MainActor
final class GofileDownloadManager: ObservableObject {
  static let shared = GofileDownloadManager()
  @Published private(set) var items: [GofileBatchDownload] = []
  private var observations: [UUID: AnyCancellable] = [:]
  var active: [GofileBatchDownload] { items.filter(\.running) }
  var unfinished: [GofileBatchDownload] { items.filter { $0.phase != .finished && $0.phase != .cancelled } }
  var finished: [GofileBatchDownload] { items.filter { $0.phase == .finished || $0.phase == .cancelled } }
  var resumable: [GofileBatchDownload] { items.filter { $0.canResume && $0.gate?.needsPassword != true } }

  func batch(url: URL, listing: GofileListing) -> GofileBatchDownload {
    enqueue(url: url, selection: .listing(listing))
  }

  func download(url: URL, entry: GofileEntry) -> GofileBatchDownload {
    enqueue(url: url, selection: .file(entry))
  }

  func download(for entry: GofileEntry) -> GofileBatchDownload? {
    items.first { $0.sourceKey == GofileDownloadSelection.file(entry).key && $0.phase != .cancelled }
  }

  private func enqueue(url: URL, selection: GofileDownloadSelection) -> GofileBatchDownload {
    if let existing = items.first(where: { $0.sourceKey == selection.key && $0.phase != .cancelled }) { return existing }
    let batch = GofileBatchDownload(url: url, selection: selection)
    observations[batch.id] = batch.objectWillChange
      .throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] _ in self?.objectWillChange.send() }
    items.append(batch)
    batch.start(selection.listing)
    return batch
  }

  func pauseAll() { items.forEach { $0.pause() } }
  func resumeAll() { resumable.forEach { $0.resume() } }
  func clearFinished() { finished.forEach(remove) }
  func backgrounded() { pauseAll() }

  func remove(_ batch: GofileBatchDownload) {
    guard batch.phase == .finished || batch.phase == .cancelled else { return }
    observations[batch.id] = nil
    items.removeAll { $0.id == batch.id }
  }
}

struct GofileBatchRow: View {
  @ObservedObject var batch: GofileBatchDownload
  let manager: GofileDownloadManager
  var body: some View {
    NavigationLink { GofileBatchView(batch: batch) } label: {
      VStack(alignment: .leading, spacing: 6) {
        Label(batch.title, forumSymbol: "folder").appFont(.headline).lineLimit(2)
        Text(AppText.format("%@ saved · %@ skipped · %@ pending", String(describing: batch.completed), String(describing: batch.skipped.count), String(describing: batch.pending)))
          .appFont(.caption).foregroundStyle(.secondary)
        if batch.running {
          if let progress = batch.progress { ProgressView(value: progress) }
          else { ProgressView() }
          Text(batch.current).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
        } else {
          Text(status).appFont(.caption).foregroundStyle(.secondary)
        }
      }.padding(.vertical, 4)
    }.swipeActions {
      if batch.phase == .finished || batch.phase == .cancelled {
        Button(AppText.text("Remove from list"), forumSymbol: "xmark") { manager.remove(batch) }
      }
    }
  }
  private var status: String {
    switch batch.phase {
    case .idle: return AppText.text("Preparing downloads")
    case .running: return AppText.text("Downloading")
    case .paused: return batch.issue ?? AppText.text("Paused")
    case .finished: return AppText.text("Finished")
    case .cancelled: return batch.issue ?? AppText.text("Stopped")
    }
  }
}

// Keep folder discovery attached to the app after its download page is dismissed.
struct GofileDownloadSurfaces: View {
  @ObservedObject var manager: GofileDownloadManager
  var body: some View {
    ZStack {
      ForEach(manager.items) { batch in GofileDownloadSurface(session: batch.session) }
    }.frame(width: 1, height: 1).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
  }
}

private struct GofileDownloadSurface: View {
  @ObservedObject var session: GofileSession
  var body: some View {
    if !session.showingWebsite { GofileWebSurface(webView: session.webView) }
  }
}
