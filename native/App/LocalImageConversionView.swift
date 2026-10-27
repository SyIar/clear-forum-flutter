import SwiftUI
import UIKit

/// One bounded worker for both completed downloads and recursive manual requests.
/// Only request roots are journaled; restarting safely skips already converted files.
@MainActor final class LocalImageConversionManager: ObservableObject {
  static let shared = LocalImageConversionManager()
  @Published private(set) var pending: [[String]] = []
  @Published private(set) var running = false
  @Published private(set) var current = ""
  @Published private(set) var total = 0
  @Published private(set) var completed = 0
  @Published private(set) var converted = 0
  @Published private(set) var skipped = 0
  @Published private(set) var failed = 0
  @Published private(set) var savedBytes: Int64 = 0
  @Published private(set) var error: String?
  private var worker: Task<Void, Never>?
  private var suspended = false
  private var writable = true
  private let journal = "lossless-image-conversion"

  private init() {
    do { pending = try FileDownloadStore.load([[String]].self, name: journal) ?? [] }
    catch { writable = false; error = "Could not restore conversion requests. Original files were kept." }
  }
  var activeFiles: [URL] {
    guard running, let root = documents() else { return [] }
    return pending.map { $0.reduce(root) { $0.appendingPathComponent($1) } }
  }
  private func documents() -> URL? {
    try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
  }
  func enqueue(file: URL) {
    guard file.pathExtension.lowercased() == "png", let root = documents()?.resolvingSymlinksInPath() else { return }
    let resolved = file.standardizedFileURL.resolvingSymlinksInPath()
    guard resolved.path.hasPrefix(root.path + "/") else { return }
    enqueue(path: Array(resolved.pathComponents.dropFirst(root.pathComponents.count)))
  }
  func enqueue(path: [String]) {
    guard writable, path.isEmpty || DownloadQueuePolicy.safePath(path) else { return }
    if !pending.contains(path) {
      if pending.isEmpty { converted = 0; skipped = 0; failed = 0; savedBytes = 0; error = nil }
      pending.append(path)
      guard persist() else { pending.removeLast(); return }
    }
    resume()
  }
  func pause() { suspended = true; worker?.cancel() }
  func stop() {
    suspended = true; worker?.cancel()
    pending = []; persist()
  }
  func resume() {
    guard UIApplication.shared.applicationState != .background else { return }
    suspended = false
    guard worker == nil, !pending.isEmpty, writable else { return }
    running = true
    worker = Task { await run() }
  }
  @discardableResult private func persist() -> Bool {
    do { try FileDownloadStore.save(pending, name: journal); return true }
    catch { error = "Could not save conversion requests. Original files were kept."; return false }
  }
  private func run() async {
    defer {
      worker = nil; running = false; current = ""
      if !suspended && !pending.isEmpty { resume() }
    }
    guard let root = documents() else { error = "The local file folder is unavailable."; suspended = true; return }
    let catalog = LocalFileCatalog(root: root)
    while let path = pending.first, !suspended, !Task.isCancelled {
      do {
        let scan = Task.detached(priority: .utility) { () throws -> [[String]] in
          let file = try catalog.url(for: path)
          if try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            return try catalog.storage(in: path).files.filter { URL(fileURLWithPath: $0.name).pathExtension.lowercased() == "png" }.map(\.path)
          }
          return file.pathExtension.lowercased() == "png" ? [path] : []
        }
        let files = try await withTaskCancellationHandler(operation: { try await scan.value }, onCancel: { scan.cancel() })
        total = files.count; completed = 0
        for file in files {
          try Task.checkCancellation()
          current = file.joined(separator: " / ")
          let task = Task.detached(priority: .utility) {
            try autoreleasepool { try LocalImageConversion.convert(file, in: catalog) }
          }
          do {
            let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            if let result {
              converted += 1; savedBytes += result.savedBytes
              HostedDownloadManager.shared.items.forEach { $0.objectWillChange.send() }
              GofileDownloadManager.shared.items.forEach { $0.objectWillChange.send() }
              NotificationCenter.default.post(name: FileDownloadStore.didInstallFile, object: nil)
            } else { skipped += 1 }
          } catch is CancellationError { throw CancellationError() }
          catch { failed += 1 }
          completed += 1
        }
      } catch is CancellationError { return }
      catch { failed += 1; error = "Some files could not be processed. They were left unchanged." }
      guard !Task.isCancelled, pending.first == path else { return }
      pending.removeFirst()
      if !persist() { suspended = true; return }
    }
  }
}

struct LocalImageConversionView: View {
  @ObservedObject private var manager = LocalImageConversionManager.shared
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("PNG → Lossless WebP").font(.headline)
          Text("Includes subfolders. Replaces an original only after exact pixel verification, and only when the result is smaller. Animation, high bit depth and unsupported metadata are kept as PNG.")
            .font(.subheadline).foregroundStyle(.secondary)
        }
        Section {
          if manager.running {
            if manager.total > 0 { ProgressView(value: Double(manager.completed), total: Double(manager.total)) }
            else { ProgressView() }
            Text(manager.current).font(.caption).lineLimit(2)
            Text("\(manager.completed) / \(manager.total)").monospacedDigit()
          }
          LabeledContent("Converted", value: "\(manager.converted)")
          LabeledContent(AppText.text("Skipped"), value: "\(manager.skipped)")
          LabeledContent("Failed", value: "\(manager.failed)")
          LabeledContent("Space saved", value: ByteCountFormatter.string(fromByteCount: manager.savedBytes, countStyle: .file))
          if let error = manager.error { Text(error).foregroundStyle(.secondary) }
          if !manager.running && !manager.pending.isEmpty {
            Button(AppText.text("Continue"), systemImage: "play") { manager.resume() }
          }
          if !manager.pending.isEmpty {
            Button(AppText.text("Cancel"), systemImage: "stop", role: .cancel) { manager.stop() }
          }
        } footer: {
          Text("Continues while you browse the app. Pauses when the app goes into the background and resumes on return. Pending requests survive app restarts.")
        }
      }.navigationTitle("Lossless WebP").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppText.text("Done")) { dismiss() } } }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}
