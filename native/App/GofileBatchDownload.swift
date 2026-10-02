import SwiftUI

@MainActor
final class GofileBatchDownload: ObservableObject, Identifiable {
  enum Phase: String, Codable { case idle, running, paused, finished, cancelled }
  struct Skipped: Identifiable, Codable {
    var id = UUID()
    let path: String
    let reason: String
  }
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
  var transferID: UUID? { plan?.next?.id }
  func contains(_ entry: GofileEntry) -> Bool { savedFiles[entry.id] != nil || plan?.pending.contains { $0.entry.id == entry.id } == true }
  func isCurrent(_ entry: GofileEntry) -> Bool { plan?.next?.entry.id == entry.id }
  let sourceKey: String
  let title: String
  private let url: URL
  lazy var session = GofileSession(url: url)
  @Published private(set) var phase = Phase.idle
  @Published private(set) var current = ""
  @Published private(set) var progress: Double?
  @Published private(set) var activity = FileTransferActivity.waiting
  @Published private(set) var completed = 0
  @Published private(set) var skipped: [Skipped] = []
  @Published private(set) var issue: String?
  @Published private(set) var gate: GofileFailure?
  @Published private(set) var directory: URL?
  @Published private(set) var savedFiles: [String: URL] = [:]
  private var plan: GofileBatchPlan?
  @Published private var worker: Task<Void, Never>?
  private var unlocked: GofileListing?
  var pending: Int { plan?.pending.count ?? 0 }
  var running: Bool { phase == .running }
  var canResume: Bool { phase == .paused && worker == nil && plan != nil && directory != nil && gate?.retryDate.map { $0 > Date() } != true }
  init(url: URL, selection: GofileDownloadSelection) {
    id = UUID(); created = Date()
    self.url = url
    sourceKey = selection.key
    title = selection.listing.title
  }
  init(record: GofileBatchRecord) throws {
    guard GofilePolicy.pageURL(record.url) != nil,
          record.plan?.pending.allSatisfy({ DownloadQueuePolicy.safePath($0.path) }) != false else { throw ReaderFailure.storage }
    id = record.id; created = record.created; sourceKey = record.sourceKey; title = record.title; url = record.url
    phase = [.finished, .cancelled].contains(record.phase) ? record.phase : .paused
    current = record.current; issue = record.issue; gate = record.gate; plan = record.plan; progress = record.progress; skipped = record.skipped
    if let folder = record.folder {
      let directory = try FileDownloadStore.folder(folder, parent: AppText.text("Gofile Downloads")); self.directory = directory
      savedFiles = try record.saved.mapValues { try FileDownloadStore.destination($0, in: directory) }
    }
    completed = savedFiles.count
  }
  var record: GofileBatchRecord {
    let prefix = directory?.pathComponents.count ?? 0
    return GofileBatchRecord(id: id, created: created, sourceKey: sourceKey, title: title, url: url, phase: phase,
      current: current, issue: issue, gate: gate, folder: directory?.lastPathComponent,
      saved: savedFiles.mapValues { Array($0.pathComponents.dropFirst(prefix)) }, skipped: skipped, plan: plan, progress: progress)
  }

  func start(_ listing: GofileListing) {
    guard worker == nil, phase == .idle || phase == .finished || phase == .cancelled else { return }
    plan = nil; directory = nil; unlocked = nil; savedFiles = [:]
    do {
      plan = try GofileBatchPlan(listing: listing)
      let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      let parent = documents.appendingPathComponent(AppText.text("Gofile Downloads"), isDirectory: true)
      let label = String(GofilePolicy.filename(listing.title).prefix(80)) + "-" + String(UUID().uuidString.prefix(8))
      var directory = parent.appendingPathComponent(label, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try? directory.setResourceValues(values)
      self.directory = directory; completed = 0; skipped = []; issue = nil; gate = nil
      phase = .paused; resume()
    } catch { phase = .cancelled; issue = AppText.error(error) }
    persist?()
  }
  func resume() {
    guard canResume, plan != nil, directory != nil else { return }
    phase = .running; issue = nil; gate = nil
    worker = Task { [weak self] in
      guard let self else { return }
      await self.run()
    }
    persist?()
  }
  func pause() {
    resumeOnForeground = false
    guard running else { return }
    phase = .paused; worker?.cancel(); session.stop()
    persist?()
  }
  func cancel() {
    resumeOnForeground = false
    worker?.cancel(); session.stop(); phase = .cancelled; issue = nil; gate = nil
    persist?()
  }
  func skip() {
    guard phase == .paused, worker == nil, let item = plan?.next else { return }
    // Skipping is local; it never issues another request during a server cooldown.
    skipped.append(Skipped(path: item.path.joined(separator: "/"), reason: issue ?? AppText.text("Skipped")))
    if let transferID { FileDownloadStore.remove(transferID.uuidString) }
    plan?.advance(); unlocked = nil; persist?()
    if gate?.retryDate.map({ $0 > Date() }) == true { return }
    resume()
  }
  func unlock(_ password: String) async {
    guard canResume, gate?.needsPassword == true else { return }
    phase = .running
    do {
      unlocked = try await session.unlock(password)
      guard phase == .running else { return }
      phase = .paused; gate = nil; issue = nil; resume()
    } catch {
      guard phase == .running else { return }
      phase = .paused; gate = error as? GofileFailure; issue = AppText.error(error)
    }
  }
  func returnFromWebsite() {
    guard phase == .paused, worker == nil, let item = plan?.next, item.entry.folder,
          let listing = session.availableListing, listing.page == item.page else { return }
    unlocked = listing; gate = nil; issue = nil; resume()
  }
  private func run() async {
    defer { worker = nil; persist?(); if UIApplication.shared.applicationState == .active { foregrounded() } }
    while let item = plan?.next, let directory {
      if Task.isCancelled { return }
      current = item.path.joined(separator: "/"); progress = nil
      do {
        if let recovered = try FileDownloadStore.recovered(item.id, path: item.path, directory: directory) {
          savedFiles[item.entry.id] = recovered; completed += 1; plan?.advance()
          if persist?() == true { FileDownloadStore.acknowledge(item.id) }; FileBackgroundEvents.saved(item.id); continue
        }
        if item.entry.folder {
          activity = .readingFolder
          let listing: GofileListing
          if let cached = unlocked { listing = cached; unlocked = nil }
          else { listing = try await session.fetch(item.entry.pageURL, page: item.page) }
          try Task.checkCancellation()
          let target = try FileDownloadStore.destination(item.path, in: directory)
          try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
          try plan?.expand(listing)
        } else if TorrentMetadata.isTorrent(name: item.entry.name, mime: item.entry.mime) {
          skipped.append(Skipped(path: current, reason: AppText.text("Use Copy magnet in the file list."))); plan?.advance()
          continue
        } else {
          let file = try await session.transfer(item.entry, checkpointID: item.id,
            activity: { [weak self] value in self?.activity = value }) { [weak self] value in self?.progress = value }
          defer { GofileFileTransfer.remove(file) }
          try Task.checkCancellation()
          let destination = try FileDownloadStore.install(file, id: item.id, path: item.path, directory: directory)
          savedFiles[item.entry.id] = destination
          completed += 1; plan?.advance()
          if persist?() == true { FileDownloadStore.acknowledge(item.id) }; FileBackgroundEvents.saved(item.id)
        }
        persist?()
        if UIApplication.shared.applicationState != .active, pending > 0 { phase = .paused; resumeOnForeground = true; return }
        // Pace metadata and file requests, including empty/small items. No automatic retry loop.
        try await Task.sleep(for: .milliseconds(700))
      } catch is CancellationError { return }
      catch {
        guard !Task.isCancelled else { return }
        let failure = error as? GofileFailure
        if [GofileFailure.notFound, .expired, .access, .premium, .unavailable].contains(where: { $0 == failure }) {
          skipped.append(Skipped(path: current, reason: AppText.error(error))); plan?.advance()
          do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
          continue
        }
        issue = AppText.error(error); gate = failure; phase = .paused; persist?(); FileBackgroundEvents.saved(item.id); return
      }
    }
    guard !Task.isCancelled else { return }
    current = ""; progress = nil; phase = .finished
  }
}
