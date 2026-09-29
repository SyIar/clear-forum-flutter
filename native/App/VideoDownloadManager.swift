import SwiftUI
import UIKit

@MainActor
final class VideoDownloadManager: ObservableObject {
  static let shared = VideoDownloadManager()
  @Published private(set) var items: [VideoDownload] = []
  @Published var showingManager = false
  @Published var storageError: String?
  private var writable = true
  private var schedulePending = false
  private var inBackground = false
  private var returnToForeground = Set<UUID>()
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid
  private var lastProgressUpdate = Date.distantPast
  private init() {
    do {
      var seen = Set<UUID>()
      items = try VideoDownloadStore.load().filter { seen.insert($0.id).inserted && MediaPolicy.allowed($0.source) }.map(VideoDownload.init(record:))
    } catch {
      writable = false
      storageError = "Could not restore the download list. Existing records are kept; new tasks will only be kept while the app is open."
    }
  }
  func existing(for source: URL) -> VideoDownload {
    items.last(where: { $0.source == source && $0.phase != .cancelled }) ?? VideoDownload(source: source)
  }
  func enqueue(_ item: VideoDownload) {
    if !items.contains(where: { $0.id == item.id }) { items.append(item) }
    changed()
  }
  func changed(persist: Bool = true) {
    if !persist {
      guard Date().timeIntervalSince(lastProgressUpdate) >= 0.15 else { return }
      lastProgressUpdate = Date(); objectWillChange.send(); return
    }
    objectWillChange.send()
    save()
    if inBackground {
      if !items.contains(where: \.occupiesSlot) { endBackgroundTask() }
      return
    }
    guard !schedulePending else { return }
    schedulePending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      defer { self.schedulePending = false }
      guard !self.inBackground else { return }
      for item in self.items where self.returnToForeground.contains(item.id) {
        if item.phase == .paused {
          self.returnToForeground.remove(item.id); item.resume()
        } else if item.phase == .saved || item.phase == .failed || item.phase == .cancelled {
          self.returnToForeground.remove(item.id)
        }
      }
      var slots = max(0, 2 - self.items.filter(\.occupiesSlot).count)
      for item in self.items where item.phase == .queued {
        guard slots > 0 else { break }
        slots -= 1; item.beginQueued()
      }
    }
  }
  private func save() {
    guard writable else { return }
    do { try VideoDownloadStore.save(items.map(\.record)) }
    catch { storageError = "Could not save the download list. Keep the app open and check free space." }
  }
  func remove(_ item: VideoDownload) {
    guard !item.busy else { return }
    returnToForeground.remove(item.id)
    item.discard(); items.removeAll { $0.id == item.id }; changed()
  }
  func clearFinished() {
    for item in items.filter({ $0.phase == .saved || $0.phase == .cancelled }) { remove(item) }
  }
  func pauseAll() { for item in items where item.canPause { returnToForeground.remove(item.id); item.pause() } }
  func resumeAll() { for item in items where item.canResume { item.resume() } }
  func backgrounded() {
    guard !inBackground else { return }
    inBackground = true
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save video download breakpoints") { [weak self] in
      Task { @MainActor in self?.save(); self?.endBackgroundTask() }
    }
    for item in items where item.canPause { returnToForeground.insert(item.id); item.pause() }
    save()
    if !items.contains(where: \.occupiesSlot) { endBackgroundTask() }
  }
  func foregrounded() {
    guard inBackground else { return }
    inBackground = false; endBackgroundTask(); changed()
  }
  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid
  }
  var active: [VideoDownload] { items.filter { $0.busy } }
  var unfinished: [VideoDownload] { items.filter { ![.saved, .cancelled].contains($0.phase) } }
  var progress: Double? {
    let moving = active.filter { $0.phase == .downloading || $0.phase == .saving }
    guard !moving.isEmpty, moving.allSatisfy({ $0.expected > 0 }) else { return nil }
    let total = moving.reduce(0.0) { $0 + Double($1.expected) }
    let received = moving.reduce(0.0) { $0 + Double(min($1.received, $1.expected)) }
    return min(1, max(0, received / total))
  }
}
