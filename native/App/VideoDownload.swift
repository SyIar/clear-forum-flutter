import AVFoundation
import Combine
import Photos
import UIKit

@MainActor
final class VideoDownload: ObservableObject {
  enum Phase { case idle, authorizing, downloading, saving, saved, failed }
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var progress: Double?
  @Published private(set) var message = ""
  private(set) var exportFile: URL?
  private let id = UUID()
  private let source: URL
  private var generation = 0
  private var transfer: MediaFileTransfer?
  private var resolver: TurboResolver?
  private var work: Task<Void, Never>?
  // Transfers survive navigation back, without retaining a player or reader.
  private static var active: [UUID: VideoDownload] = [:]
  private init(source: URL) { self.source = source }
  static func existingOrNew(for source: URL) -> VideoDownload {
    active.values.first { $0.source == source } ?? VideoDownload(source: source)
  }
  var busy: Bool { phase == .authorizing || phase == .downloading || phase == .saving }
  var canCancel: Bool { phase == .authorizing || phase == .downloading }
  func start(url: URL, cookies: [HTTPCookie], turboID: String?, referer: URL) {
    guard !busy else { return }
    guard Self.active.count < 2 else { fail("Two downloads are already running. Please wait for one to finish."); return }
    removeFile()
    generation += 1
    let epoch = generation
    phase = .authorizing; message = "Requesting Photos access"; progress = nil
    Self.active[id] = self
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
      Task { @MainActor in
        guard let self, self.generation == epoch else { return }
        guard status == .authorized else {
          self.fail("Allow adding photos in Settings to save videos."); return
        }
        if let turboID { self.resolve(turboID, referer: referer, epoch: epoch) }
        else { self.begin(url: url, cookies: cookies, epoch: epoch) }
      }
    }
  }
  private func resolve(_ id: String, referer: URL, epoch: Int) {
    phase = .downloading; message = "Refreshing download source"
    let resolver = TurboResolver(id: id, cookies: [], referer: referer, event: { _, _ in }, completion: { [weak self] result in
      guard let self, self.generation == epoch else { return }
      self.resolver = nil
      switch result {
      case .success(let media): self.begin(url: media.url, cookies: media.cookies, epoch: epoch)
      case .failure(let error): self.fail(error.reason)
      }
    })
    self.resolver = resolver; resolver.start()
  }
  private func begin(url: URL, cookies: [HTTPCookie], epoch: Int) {
    phase = .downloading; message = "Downloading video"
    let transfer = MediaFileTransfer(limit: MediaFilePolicy.videoLimit, cookies: cookies, progress: { [weak self] value in
      guard let self, self.generation == epoch else { return }
      self.progress = value
    }, completion: { [weak self] result in
      guard let self, self.generation == epoch else {
        if case .success(let file) = result { try? FileManager.default.removeItem(at: file) }; return
      }
      self.transfer = nil
      switch result {
      case .success(let file): self.validateAndSave(file, epoch: epoch)
      case .failure(let error):
        if error is CancellationError { self.phase = .idle; self.message = "Download canceled"; Self.active[self.id] = nil }
        else { self.fail((error as? MediaFileError)?.message ?? "Could not download this video.") }
      }
    })
    self.transfer = transfer; transfer.start(url)
  }
  private func validateAndSave(_ file: URL, epoch: Int) {
    exportFile = file
    phase = .saving; message = "Saving to Photos"; progress = 1
    work = Task { [weak self] in
      do {
        let tracks = try await AVURLAsset(url: file).loadTracks(withMediaType: .video)
        guard let self, self.generation == epoch, !Task.isCancelled else { return }
        guard !tracks.isEmpty else { self.fail("The downloaded file has no supported video track."); return }
        PHPhotoLibrary.shared().performChanges {
          let request = PHAssetCreationRequest.forAsset()
          request.addResource(with: .video, fileURL: file, options: nil)
        } completionHandler: { [weak self] success, _ in
          Task { @MainActor in
            guard let self, self.generation == epoch else { return }
            if success {
              self.phase = .saved; self.message = "Saved to Photos"; self.progress = 1
              self.removeFile(); Self.active[self.id] = nil
              UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
              self.fail("Photos could not import this format. You can save the downloaded file to Files.")
            }
            self.work = nil
          }
        }
      } catch {
        guard let self, self.generation == epoch else { return }
        self.fail("This file cannot be imported as a video. You can save it to Files.")
      }
    }
  }
  private func fail(_ message: String) {
    self.message = message; phase = .failed
    Self.active[id] = nil
  }
  func cancel() {
    guard canCancel else { return }
    generation += 1
    resolver?.cancel(); resolver = nil
    transfer?.cancel(); transfer = nil; work?.cancel(); work = nil
    phase = .idle; message = "Download canceled"; progress = nil
    Self.active[id] = nil
  }
  private func removeFile() {
    if let exportFile { try? FileManager.default.removeItem(at: exportFile); self.exportFile = nil }
  }
  deinit { if let exportFile { try? FileManager.default.removeItem(at: exportFile) } }
}
