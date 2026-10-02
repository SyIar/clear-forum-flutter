import ForumUI
import SwiftUI
import Combine

@MainActor
final class HostedDownloadManager: ObservableObject {
  static let shared = HostedDownloadManager()
  @Published private(set) var items: [HostedBatchDownload] = []
  @Published private(set) var storageError: String?
  private var writable = true
  private var observations: [UUID: AnyCancellable] = [:]
  private init() {
    do { items = try (FileDownloadStore.load([HostedBatchRecord].self, name: "hosted") ?? []).map(HostedBatchDownload.init(record:)); items.forEach(observe) }
    catch { writable = false; storageError = AppText.text("Download history could not be restored. Existing files were preserved.") }
  }
  private func observe(_ batch: HostedBatchDownload) {
    batch.persist = { [weak self] in self?.save() ?? false }
    observations[batch.id] = batch.objectWillChange.throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] _ in self?.objectWillChange.send() }
  }
  @discardableResult private func save() -> Bool {
    guard writable else { return false }
    do { try FileDownloadStore.save(items.map(\.record), name: "hosted"); storageError = nil; return true }
    catch { storageError = AppText.text("Could not save download history."); return false }
  }
  func download(for entry: HostedFileEntry) -> HostedBatchDownload? { items.first { $0.contains(entry) && $0.phase != .cancelled } }
  var active: [HostedBatchDownload] { items.filter(\.running) }
  var unfinished: [HostedBatchDownload] { items.filter { !$0.finished } }
  var resumable: [HostedBatchDownload] { items.filter(\.canResume) }
  func enqueue(_ listing: HostedFileListing) -> HostedBatchDownload {
    let key = HostedFilePolicy.key(listing.url)
    if let existing = items.first(where: { $0.sourceKey == key && !$0.finished }) { return existing }
    let batch = HostedBatchDownload(listing: listing)
    observe(batch)
    items.append(batch); batch.start()
    return batch
  }
  func pauseAll() { items.forEach { $0.pause() } }
  func backgrounded() { items.forEach { $0.backgrounded() } }
  func foregrounded() { items.forEach { $0.foregrounded() } }
  func resumeAll() { resumable.forEach { $0.resume() } }
  func clearFinished() { items.filter(\.finished).forEach(remove) }
  func remove(_ item: HostedBatchDownload) {
    guard item.finished else { return }
    observations[item.id] = nil; items.removeAll { $0.id == item.id }
    save()
  }
}

@MainActor
final class HostedBatchDownload: ObservableObject, Identifiable {
  enum Phase: String, Codable { case idle, running, paused, finished, cancelled }
  struct Saved: Identifiable, Codable { var id = UUID(); let name: String; let url: URL; var entryKey: String? }
  struct Skipped: Identifiable, Codable { var id = UUID(); let name: String; let reason: String }
  let id: UUID
  let created: Date
  var persist: (() -> Bool)?
  private var resumeOnForeground = false
  func backgrounded() {
    guard running else { return }
    if activity != .downloading && activity != .saving { pause() }
    resumeOnForeground = true
  }
  func foregrounded() { if resumeOnForeground && canResume { resumeOnForeground = false; resume() } }
  var transferID: UUID? { plan?.pending.first?.id }
  func contains(_ entry: HostedFileEntry) -> Bool { saved.contains { $0.entryKey == entry.id } || plan?.pending.contains { $0.entry.id == entry.id } == true }
  func file(for entry: HostedFileEntry) -> URL? { saved.first { $0.entryKey == entry.id }?.url }
  func isCurrent(_ entry: HostedFileEntry) -> Bool { plan?.pending.first?.entry.id == entry.id }
  let listing: HostedFileListing
  var sourceKey: String { HostedFilePolicy.key(listing.url) }
  var provider: String { HostedFilePolicy.provider(listing.url)?.title ?? AppText.text("Files") }
  @Published private(set) var phase = Phase.idle
  @Published private(set) var current = ""
  @Published private(set) var progress: Double?
  @Published private(set) var activity = FileTransferActivity.waiting
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
  var queued: Int { activity.queuedCount(pending: pending, running: running) }
  var canResume: Bool { phase == .paused && worker == nil && directory != nil && retryAfter.map { $0 > Date() } != true }
  var status: String {
    switch phase {
    case .idle: return AppText.text("Preparing downloads")
    case .running:
      switch activity {
      case .waiting: return AppText.text("Queued")
      case .resolving: return AppText.text("Resolving download address")
      case .downloading: return AppText.text("Downloading")
      case .saving: return AppText.text("Saving file")
      case .readingFolder: return AppText.text("Reading folder")
      }
    case .paused: return issue ?? AppText.text("Paused")
    case .finished: return skipped.isEmpty ? AppText.text("All files saved") : AppText.text("Finished with skipped items")
    case .cancelled: return issue ?? AppText.text("Stopped")
    }
  }
  init(listing: HostedFileListing) { id = UUID(); created = Date(); self.listing = listing }
  init(record: HostedBatchRecord) throws {
    guard HostedFilePolicy.provider(record.listing.url) != nil,
          record.plan?.pending.allSatisfy({ DownloadQueuePolicy.safePath($0.path) }) != false else { throw ReaderFailure.storage }
    id = record.id; created = record.created; listing = record.listing; plan = record.plan
    phase = [.finished, .cancelled].contains(record.phase) ? record.phase : .paused
    current = record.current; issue = record.issue; retryAfter = record.retryAfter; progress = record.progress; skipped = record.skipped
    if let folder = record.folder {
      let directory = try FileDownloadStore.folder(folder, parent: "File Downloads"); self.directory = directory
      saved = try record.saved.map { item in
        Saved(id: item.id, name: item.name, url: try FileDownloadStore.destination(item.name.components(separatedBy: "/"), in: directory), entryKey: item.entryKey)
      }
    }
  }
  var record: HostedBatchRecord {
    HostedBatchRecord(id: id, created: created, listing: listing, phase: phase, current: current, issue: issue,
      retryAfter: retryAfter, folder: directory?.lastPathComponent, saved: saved, skipped: skipped, plan: plan, progress: progress)
  }
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
    } catch { phase = .cancelled; issue = AppText.error(error) }
    persist?()
  }
  func pause() {
    resumeOnForeground = false
    guard running else { return }
    phase = .paused; worker?.cancel()
    persist?()
  }
  func resume() {
    guard canResume else { return }
    progress = nil; activity = .waiting
    phase = .running; issue = nil; retryAfter = nil
    worker = Task { [weak self] in await self?.run() }
    persist?()
  }
  func cancel() {
    resumeOnForeground = false
    worker?.cancel(); phase = .cancelled; issue = nil; retryAfter = nil
    persist?()
  }
  func skip() {
    guard phase == .paused, worker == nil, let item = plan?.pending.first else { return }
    skipped.append(Skipped(name: item.path.joined(separator: "/"), reason: issue ?? AppText.text("Skipped")))
    if let transferID { FileDownloadStore.remove(transferID.uuidString) }
    plan?.advance(); persist?(); resume()
  }
  private func run() async {
    defer { worker = nil; persist?(); if UIApplication.shared.applicationState == .active { foregrounded() } }
    while let item = plan?.pending.first, let directory {
      if Task.isCancelled { return }
      current = item.path.joined(separator: "/"); progress = nil
      activity = .waiting
      do {
        if let recovered = try FileDownloadStore.recovered(item.id, path: item.path, directory: directory) {
          saved.append(Saved(name: current, url: recovered, entryKey: item.entry.id)); plan?.advance()
          if persist?() == true { FileDownloadStore.acknowledge(item.id) }; FileBackgroundEvents.saved(item.id); continue
        }
        if item.entry.folder {
          activity = .readingFolder
          let listing = try await client.listing(item.entry.pageURL, expandAlbum: false)
          try Task.checkCancellation()
          try plan?.expand(listing)
        } else if TorrentMetadata.isTorrent(name: item.entry.name, mime: item.entry.mime) {
          skipped.append(Skipped(name: current, reason: AppText.text("Use Copy magnet in the file list."))); plan?.advance()
        } else {
          let file = try await HostedTransfer.run(item.entry, client: client, checkpointID: item.id, activity: { [weak self] value in
            guard let self, self.running else { return }
            self.activity = value
          }) { [weak self] value in
            guard let self, self.running else { return }
            self.progress = value
          }
          defer { GofileFileTransfer.remove(file) }
          try Task.checkCancellation()
          let destination = try FileDownloadStore.install(file, id: item.id, path: item.path, directory: directory)
          saved.append(Saved(name: current, url: destination, entryKey: item.entry.id)); plan?.advance()
          if persist?() == true { FileDownloadStore.acknowledge(item.id) }; FileBackgroundEvents.saved(item.id)
        }
        current = ""; progress = nil; activity = .waiting
        persist?()
        if UIApplication.shared.applicationState != .active, pending > 0 { phase = .paused; resumeOnForeground = true; return }
        try await Task.sleep(for: .milliseconds(700))
      } catch is CancellationError { return }
      catch {
        guard !Task.isCancelled else { return }
        issue = AppText.error(error); retryAfter = (error as? HostedFileFailure)?.retryDate
        phase = .paused; persist?(); FileBackgroundEvents.saved(item.id); return
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
        Label(batch.listing.title, forumSymbol: "folder").appFont(.headline).lineLimit(2)
        Text(AppText.format("%@ · %@ saved · %@ queued", batch.provider, String(batch.saved.count), String(batch.queued))).appFont(.caption).foregroundStyle(.secondary)
        Text(batch.status).appFont(.caption).foregroundStyle(.secondary)
        if batch.running {
          if let progress = batch.progress { ProgressView(value: progress) } else { ProgressView() }
          Text(batch.current).appFont(.caption).lineLimit(1).foregroundStyle(.secondary)
        }
      }.padding(.vertical, 4)
    }.swipeActions {
      if batch.finished { Button(AppText.text("Remove from list"), forumSymbol: "xmark") { HostedDownloadManager.shared.remove(batch) } }
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
        Text(batch.listing.title).appFont(.headline)
        Text(AppText.format("%@ saved · %@ skipped · %@ queued", String(batch.saved.count), String(batch.skipped.count), String(batch.queued))).appFont(.subheadline).foregroundStyle(.secondary)
        if !batch.current.isEmpty { Text(batch.current).appFont(.subheadline).lineLimit(3) }
        Text(batch.status).appFont(.subheadline).foregroundStyle(batch.running ? Color.primary : Color.secondary)
        if batch.running {
          if let progress = batch.progress {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))%").appFont(.caption).monospacedDigit()
          } else { ProgressView() }
          Button(AppText.text("Pause"), forumSymbol: "pause", action: batch.pause)
        } else {
          if batch.phase == .paused {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              if let date = batch.retryAfter, date > context.date {
                Text(AppText.format("Try again in %@s", String(describing: Int(ceil(date.timeIntervalSince(context.date)))))).appFont(.caption).monospacedDigit()
              } else { Button(AppText.text("Continue"), forumSymbol: "play", action: batch.resume).disabled(!batch.canResume) }
            }
            Button(AppText.text("Skip this item"), forumSymbol: "forward.end", action: batch.skip).disabled(batch.pending == 0)
          }
        }
        if batch.issue != nil { Button(AppText.text("Open website"), forumSymbol: "safari") { website = batch.listing.url } }
      }
      if let directory = batch.directory {
        Section {
          Label(AppText.text("Files → On My iPhone → Forum Lite → File Downloads"), forumSymbol: "folder").appFont(.caption)
          Button(AppText.text("Export folder"), forumSymbol: "square.and.arrow.up") { export = GofileLocalFile(url: directory) }.disabled(batch.running)
        }
      }
      if !batch.saved.isEmpty {
        Section(AppText.text("Saved files")) {
          ForEach(batch.saved) { file in
            Button { preview = GofileLocalFile(url: file.url) } label: {
              Label(file.name, forumSymbol: "checkmark.circle").foregroundStyle(.primary).lineLimit(2)
            }.contextMenu { Button(AppText.text("Export file"), forumSymbol: "square.and.arrow.up") { export = GofileLocalFile(url: file.url) } }
          }
        }
      }
      if !batch.skipped.isEmpty {
        Section(AppText.text("Skipped items")) {
          ForEach(batch.skipped) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.name).appFont(.subheadline)
              Text(item.reason).appFont(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if !batch.finished { Section { Button(AppText.text("Stop batch"), forumSymbol: "stop", role: .destructive, action: batch.cancel) } }
    }.navigationTitle(AppText.text("Downloads")).navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
      .sheet(item: $export) { GofileExport(file: $0.url) }
      .navigationDestination(item: $preview) { GofileQuickLook(file: $0.url).ignoresSafeArea(.container, edges: .bottom).navigationBarTitleDisplayMode(.inline) }
      .background { ExternalBrowserPresenter(url: $website, useFileBrowser: false).frame(width: 0, height: 0) }
  }
}
