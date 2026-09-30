import SwiftUI

@MainActor
final class GofileBatchDownload: ObservableObject, Identifiable {
  enum Phase { case idle, running, paused, finished, cancelled }
  struct Skipped: Identifiable {
    let id = UUID()
    let path: String
    let reason: String
  }
  let id = UUID()
  let sourceKey: String
  let title: String
  private let url: URL
  lazy var session = GofileSession(url: url)
  @Published private(set) var phase = Phase.idle
  @Published private(set) var current = ""
  @Published private(set) var progress: Double?
  @Published private(set) var completed = 0
  @Published private(set) var skipped: [Skipped] = []
  @Published private(set) var issue: String?
  @Published private(set) var gate: GofileFailure?
  @Published private(set) var directory: URL?
  private var plan: GofileBatchPlan?
  @Published private var worker: Task<Void, Never>?
  private var unlocked: GofileListing?
  var pending: Int { plan?.pending.count ?? 0 }
  var running: Bool { phase == .running }
  var canResume: Bool { phase == .paused && worker == nil && plan != nil && directory != nil && gate?.retryDate.map { $0 > Date() } != true }
  init(url: URL, listing: GofileListing) {
    self.url = url
    sourceKey = "\(listing.id):\(listing.page)"
    title = listing.title
  }

  func start(_ listing: GofileListing) {
    guard worker == nil, phase == .idle || phase == .finished || phase == .cancelled else { return }
    plan = nil; directory = nil; unlocked = nil
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
  }
  func resume() {
    guard canResume, plan != nil, directory != nil else { return }
    phase = .running; issue = nil; gate = nil
    worker = Task { [weak self] in
      guard let self else { return }
      await self.run()
    }
  }
  func pause() {
    guard running else { return }
    phase = .paused; worker?.cancel(); session.stop()
  }
  func cancel() {
    worker?.cancel(); session.stop(); phase = .cancelled; issue = nil; gate = nil
  }
  func skip() {
    guard phase == .paused, worker == nil, let item = plan?.next else { return }
    // Skipping is local; it never issues another request during a server cooldown.
    skipped.append(Skipped(path: item.path.joined(separator: "/"), reason: issue ?? AppText.text("Skipped")))
    plan?.advance(); unlocked = nil
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
    defer { worker = nil }
    while let item = plan?.next, let directory {
      if Task.isCancelled { return }
      current = item.path.joined(separator: "/"); progress = nil
      do {
        if item.entry.folder {
          let listing: GofileListing
          if let cached = unlocked { listing = cached; unlocked = nil }
          else { listing = try await session.fetch(item.entry.pageURL, page: item.page) }
          try Task.checkCancellation()
          let target = item.path.reduce(directory) { $0.appendingPathComponent($1, isDirectory: true) }
          try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
          try plan?.expand(listing)
        } else if TorrentMetadata.isTorrent(name: item.entry.name, mime: item.entry.mime) {
          skipped.append(Skipped(path: current, reason: AppText.text("Use Copy magnet in the file list."))); plan?.advance()
          continue
        } else {
          let file = try await session.transfer(item.entry) { [weak self] value in self?.progress = value }
          defer { GofileFileTransfer.remove(file) }
          try Task.checkCancellation()
          let destination = item.path.reduce(directory) { $0.appendingPathComponent($1) }
          try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
          // moveItem refuses to overwrite an existing file. Only fully validated transfers reach here.
          try FileManager.default.moveItem(at: file, to: destination)
          completed += 1; plan?.advance()
        }
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
        issue = AppText.error(error); gate = failure; phase = .paused; return
      }
    }
    guard !Task.isCancelled else { return }
    current = ""; progress = nil; phase = .finished
  }
}
