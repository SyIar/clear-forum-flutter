import SwiftUI
import Combine

@MainActor
final class HostedDownloadManager: ObservableObject {
  static let shared = HostedDownloadManager()
  @Published private(set) var items: [HostedBatchDownload] = []
  private var observations: [UUID: AnyCancellable] = [:]
  var active: [HostedBatchDownload] { items.filter(\.running) }
  var unfinished: [HostedBatchDownload] { items.filter { !$0.finished } }
  var resumable: [HostedBatchDownload] { items.filter(\.canResume) }
  func enqueue(_ listing: HostedFileListing) -> HostedBatchDownload {
    let key = HostedFilePolicy.key(listing.url)
    if let existing = items.first(where: { $0.sourceKey == key && !$0.finished }) { return existing }
    let batch = HostedBatchDownload(listing: listing)
    observations[batch.id] = batch.objectWillChange
      .throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] _ in self?.objectWillChange.send() }
    items.append(batch); batch.start()
    return batch
  }
  func pauseAll() { items.forEach { $0.pause() } }
  func resumeAll() { resumable.forEach { $0.resume() } }
  func clearFinished() { items.filter(\.finished).forEach(remove) }
  func remove(_ item: HostedBatchDownload) {
    guard item.finished else { return }
    observations[item.id] = nil; items.removeAll { $0.id == item.id }
  }
}

@MainActor
final class HostedBatchDownload: ObservableObject, Identifiable {
  enum Phase { case idle, running, paused, finished, cancelled }
  struct Saved: Identifiable { let id = UUID(); let name: String; let url: URL }
  struct Skipped: Identifiable { let id = UUID(); let name: String; let reason: String }
  let id = UUID()
  let listing: HostedFileListing
  var sourceKey: String { HostedFilePolicy.key(listing.url) }
  var provider: String { HostedFilePolicy.provider(listing.url)?.title ?? "Files" }
  @Published private(set) var phase = Phase.idle
  @Published private(set) var current = ""
  @Published private(set) var progress: Double?
  @Published private(set) var saved: [Saved] = []
  @Published private(set) var skipped: [Skipped] = []
  @Published private(set) var issue: String?
  @Published private(set) var retryAfter: Date?
  @Published private(set) var directory: URL?
  @Published private var worker: Task<Void, Never>?
  private var plan: HostedBatchPlan?
  private let client = HostedFileClient()
  var running: Bool { phase == .running }
  var finished: Bool { phase == .finished || phase == .cancelled }
  var pending: Int { plan?.pending.count ?? 0 }
  var canResume: Bool { phase == .paused && worker == nil && directory != nil && retryAfter.map { $0 > Date() } != true }
  var status: String {
    switch phase {
    case .idle: return "Preparing downloads"
    case .running: return "Downloading"
    case .paused: return issue ?? "Paused"
    case .finished: return skipped.isEmpty ? "All files saved" : "Finished with skipped items"
    case .cancelled: return issue ?? "Stopped"
    }
  }
  init(listing: HostedFileListing) { self.listing = listing }
  func start() {
    guard phase == .idle else { return }
    do {
      plan = try HostedBatchPlan(listing)
      let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let label = String(GofilePolicy.filename(listing.title).prefix(80)) + "-" + String(id.uuidString.prefix(8))
      var folder = documents.appendingPathComponent("File Downloads", isDirectory: true).appendingPathComponent(label, isDirectory: true)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      var values = URLResourceValues(); values.isExcludedFromBackup = true; try? folder.setResourceValues(values)
      directory = folder; phase = .paused; resume()
    } catch { phase = .cancelled; issue = error.localizedDescription }
  }
  func pause() {
    guard running else { return }
    phase = .paused; worker?.cancel()
  }
  func resume() {
    guard canResume else { return }
    phase = .running; issue = nil; retryAfter = nil
    worker = Task { [weak self] in await self?.run() }
  }
  func cancel() {
    worker?.cancel(); phase = .cancelled; issue = nil; retryAfter = nil
  }
  func skip() {
    guard phase == .paused, worker == nil, let item = plan?.pending.first else { return }
    skipped.append(Skipped(name: item.path.joined(separator: "/"), reason: issue ?? "Skipped"))
    plan?.advance(); resume()
  }
  private func run() async {
    defer { worker = nil }
    while let item = plan?.pending.first, let directory {
      if Task.isCancelled { return }
      current = item.path.joined(separator: "/"); progress = nil
      do {
        if item.entry.folder {
          let listing = try await client.listing(item.entry.pageURL, expandAlbum: false)
          try Task.checkCancellation()
          try plan?.expand(listing)
        } else if TorrentMetadata.isTorrent(name: item.entry.name, mime: item.entry.mime) {
          skipped.append(Skipped(name: current, reason: "Use Copy magnet in the file list.")); plan?.advance()
          continue
        } else {
          let file = try await HostedTransfer.run(item.entry, client: client) { [weak self] value in self?.progress = value }
          defer { GofileFileTransfer.remove(file) }
          try Task.checkCancellation()
          let destination = item.path.reduce(directory) { $0.appendingPathComponent($1) }
          try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
          try FileManager.default.moveItem(at: file, to: destination)
          saved.append(Saved(name: current, url: destination)); plan?.advance()
        }
        try await Task.sleep(for: .milliseconds(700))
      } catch is CancellationError { return }
      catch {
        guard !Task.isCancelled else { return }
        issue = error.localizedDescription; retryAfter = (error as? HostedFileFailure)?.retryDate
        phase = .paused; return
      }
    }
    guard !Task.isCancelled else { return }
    current = ""; progress = nil; phase = .finished
  }
}

struct HostedBatchRow: View {
  @ObservedObject var batch: HostedBatchDownload
  var body: some View {
    NavigationLink { HostedBatchView(batch: batch) } label: {
      VStack(alignment: .leading, spacing: 6) {
        Label(batch.listing.title, systemImage: "folder").font(.headline).lineLimit(2)
        Text("\(batch.provider) · \(batch.saved.count) saved · \(batch.pending) pending").font(.caption).foregroundStyle(.secondary)
        if batch.running {
          if let progress = batch.progress { ProgressView(value: progress) } else { ProgressView() }
          Text(batch.current).font(.caption).lineLimit(1).foregroundStyle(.secondary)
        } else { Text(batch.status).font(.caption).foregroundStyle(.secondary) }
      }.padding(.vertical, 4)
    }.swipeActions {
      if batch.finished { Button("Remove from list", systemImage: "xmark") { HostedDownloadManager.shared.remove(batch) } }
    }
  }
}

struct HostedBatchView: View {
  @ObservedObject var batch: HostedBatchDownload
  @State private var export: GofileLocalFile?
  @State private var preview: GofileLocalFile?
  @State private var website: URL?
  var body: some View {
    List {
      Section {
        Text(batch.listing.title).font(.headline)
        Text("\(batch.saved.count) saved · \(batch.skipped.count) skipped · \(batch.pending) pending").font(.subheadline).foregroundStyle(.secondary)
        if !batch.current.isEmpty { Text(batch.current).font(.subheadline).lineLimit(3) }
        if batch.running {
          if let progress = batch.progress {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
          } else { ProgressView() }
          Button("Pause", systemImage: "pause", action: batch.pause)
        } else {
          Text(batch.status).foregroundStyle(.secondary)
          if batch.phase == .paused {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              if let date = batch.retryAfter, date > context.date {
                Text("Try again in \(Int(ceil(date.timeIntervalSince(context.date))))s").font(.caption).monospacedDigit()
              } else { Button("Continue", systemImage: "play", action: batch.resume).disabled(!batch.canResume) }
            }
            Button("Skip this item", systemImage: "forward.end", action: batch.skip).disabled(batch.pending == 0)
          }
        }
        if batch.issue != nil { Button("Open website", systemImage: "safari") { website = batch.listing.url } }
      }
      if let directory = batch.directory {
        Section {
          Label("Files → On My iPhone → Forum Lite → File Downloads", systemImage: "folder").font(.caption)
          Button("Export folder", systemImage: "square.and.arrow.up") { export = GofileLocalFile(url: directory) }.disabled(batch.running)
        }
      }
      if !batch.saved.isEmpty {
        Section("Saved files") {
          ForEach(batch.saved) { file in
            Button { preview = GofileLocalFile(url: file.url) } label: {
              Label(file.name, systemImage: "checkmark.circle").foregroundStyle(.primary).lineLimit(2)
            }.contextMenu { Button("Export file", systemImage: "square.and.arrow.up") { export = GofileLocalFile(url: file.url) } }
          }
        }
      }
      if !batch.skipped.isEmpty {
        Section("Skipped items") {
          ForEach(batch.skipped) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.name).font(.subheadline)
              Text(item.reason).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if !batch.finished { Section { Button("Stop batch", systemImage: "stop", role: .destructive, action: batch.cancel) } }
    }.navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
      .sheet(item: $export) { GofileExport(file: $0.url) }
      .navigationDestination(item: $preview) { GofileQuickLook(file: $0.url).ignoresSafeArea(.container, edges: .bottom).navigationBarTitleDisplayMode(.inline) }
      .background { ExternalBrowserPresenter(url: $website, useFileBrowser: false).frame(width: 0, height: 0) }
  }
}
