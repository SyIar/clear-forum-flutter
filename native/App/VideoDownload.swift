import AVFoundation
import Combine
import Photos
import UIKit

@MainActor
final class VideoDownload: ObservableObject, Identifiable {
  enum Phase: String, Codable { case idle, queued, authorizing, downloading, pausing, paused, saving, saved, failed, cancelled }
  @Published private(set) var phase = Phase.idle
  @Published private(set) var progress: Double?
  @Published private(set) var message = ""
  @Published private(set) var received: Int64 = 0
  @Published private(set) var expected: Int64 = 0
  private(set) var exportFile: URL?
  let id: UUID
  let source: URL
  let created: Date
  let origin: VideoOrigin?
  var displayName: String {
    if let title = origin?.title, !title.isEmpty { return title }
    let name = source.lastPathComponent.removingPercentEncoding ?? source.lastPathComponent
    return ["mp4", "mov", "m4v", "webm"].contains(source.pathExtension.lowercased()) ? name : AppText.text("Video")
  }
  private(set) var context: VideoDownloadContext?
  private var generation = 0
  private var transfer: MediaFileTransfer?
  private var resolver: TurboResolver?
  private var work: Task<Void, Never>?
  private var resumeData: Data?
  init(source: URL) { self.source = source; id = UUID(); created = Date(); origin = VideoOrigins.get(source) }
  init(record: VideoDownloadRecord) {
    id = record.id; source = record.source; created = record.created; context = record.context
    origin = record.origin
    received = record.received; expected = record.expected
    progress = expected > 0 ? min(1, Double(received) / Double(expected)) : nil
    exportFile = VideoDownloadStore.localFile(record.localFilename, id: id)
    resumeData = VideoDownloadStore.resumeData(id)
    if record.phase == .saved || record.phase == .cancelled {
      phase = record.phase; message = record.phase == .saved ? AppText.text("Saved to Photos") : AppText.text("Canceled")
    }
    else {
      phase = .paused
      message = exportFile != nil ? AppText.text("File ready. Continue to save to Photos.") :
        resumeData != nil ? AppText.text("Ready to resume from the saved breakpoint.") : AppText.text("No saved breakpoint. Continue will restart this file.")
    }
  }
  static func existingOrNew(for source: URL) -> VideoDownload { VideoDownloadManager.shared.existing(for: source) }
  var busy: Bool { [.queued, .authorizing, .downloading, .pausing, .saving].contains(phase) }
  var occupiesSlot: Bool { [.authorizing, .downloading, .pausing, .saving].contains(phase) }
  var canCancel: Bool { phase != .idle && phase != .saved && phase != .saving && phase != .cancelled }
  var canPause: Bool { [.queued, .authorizing, .downloading].contains(phase) }
  var canResume: Bool { [.paused, .failed].contains(phase) && context != nil }
  var hasBreakpoint: Bool { resumeData != nil }
  var record: VideoDownloadRecord {
    VideoDownloadRecord(id: id, source: source, created: created, phase: phase,
      context: phase == .saved || phase == .cancelled ? nil : context,
      received: received, expected: expected, localFilename: exportFile?.lastPathComponent, origin: origin)
  }

  func start(url: URL, cookies: [HTTPCookie], turboID: String?, referer: URL, direct: Bool = false) {
    guard !busy else { return }
    guard MediaPolicy.allowed(url), MediaPolicy.allowed(referer) else { return }
    removeFile(); setResumeData(nil)
    context = VideoDownloadContext(url: url, cookies: cookies.filter { MediaPolicy.cookieMatches($0, url) }.map(VideoDownloadCookie.init),
      turboID: turboID, referer: referer, direct: direct)
    received = 0; expected = 0; progress = nil
    phase = .queued; message = AppText.text("Queued")
    VideoDownloadManager.shared.enqueue(self)
  }
  func resume() {
    guard canResume else { return }
    if resumeData == nil && exportFile == nil { received = 0; expected = 0; progress = nil }
    phase = .queued; message = AppText.text("Queued")
    VideoDownloadManager.shared.enqueue(self)
  }
  func beginQueued() {
    guard phase == .queued, let context else { return }
    generation += 1; let epoch = generation
    phase = .authorizing; message = AppText.text("Requesting Photos access"); changed()
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
      Task { @MainActor in
        guard let self, self.generation == epoch else { return }
        guard status == .authorized || status == .limited else { self.fail(AppText.text("Allow adding photos in Settings to save videos.")); return }
        if let file = self.exportFile { self.validateAndSave(file, epoch: epoch) }
        else if self.resumeData != nil { self.begin(context, epoch: epoch) }
        else if let turboID = context.turboID { self.resolve(turboID, referer: context.referer, epoch: epoch) }
        else { self.begin(context, epoch: epoch) }
      }
    }
  }
  private func resolve(_ id: String, referer: URL, epoch: Int) {
    phase = .downloading; message = AppText.text("Refreshing download source"); changed()
    let resolver = TurboResolver(id: id, cookies: [], referer: referer, event: { _, _ in }, completion: { [weak self] result in
      guard let self, self.generation == epoch else { return }
      self.resolver = nil
      switch result {
      case .success(let media):
        self.context?.url = media.url; self.context?.cookies = media.cookies.map(VideoDownloadCookie.init)
        if let context = self.context { self.begin(context, epoch: epoch) }
      case .failure(let error): self.fail(AppText.providerReason(error.reason))
      }
    })
    self.resolver = resolver; resolver.start()
  }
  private func begin(_ context: VideoDownloadContext, epoch: Int) {
    phase = .downloading; message = resumeData == nil ? AppText.text("Downloading") : AppText.text("Resuming"); changed()
    let transfer = MediaFileTransfer(limit: MediaFilePolicy.videoLimit, cookies: context.cookies.compactMap(\.cookie),
      progress: { [weak self] value in
        guard let self, self.generation == epoch else { return }
        self.progress = value; self.changed(persist: false)
      }, byteProgress: { [weak self] bytes, total in
        guard let self, self.generation == epoch else { return }
        self.received = bytes; self.expected = max(0, total)
      }, completion: { [weak self] result in
        guard let self, self.generation == epoch else {
          if case .success(let file) = result { try? FileManager.default.removeItem(at: file) }; return
        }
        self.transfer = nil
        switch result {
        case .success(let file):
          self.setResumeData(nil)
          do {
            let saved = try VideoDownloadStore.keep(file, id: self.id)
            self.exportFile = saved; self.validateAndSave(saved, epoch: epoch)
          } catch {
            try? FileManager.default.removeItem(at: file)
            self.fail(AppText.text("Could not keep the downloaded file. Check free space and try again."))
          }
        case .failure(let error):
          if let paused = error as? MediaTransferPaused {
            self.setResumeData(paused.resumeData); self.phase = .paused
            self.message = paused.resumeData == nil ? AppText.text("No saved breakpoint. Continue will restart this file.") : AppText.text("Paused · Breakpoint saved")
            self.changed()
          } else if let error = error as? MediaFileError {
            self.setResumeData(error.resumeData)
            self.fail(error.refreshSource ? (self.context?.turboID != nil ? AppText.text("The download link expired. Retry to refresh it and restart this file.") : AppText.text("The download link expired. Reopen the video and tap Download to refresh it.")) : error.message)
          } else if !(error is CancellationError) { self.fail(AppText.text("Could not download this video.")) }
        }
      })
    self.transfer = transfer; transfer.start(context.url, resumeData: resumeData)
  }
  private func validateAndSave(_ file: URL, epoch: Int) {
    phase = .saving; message = AppText.text("Saving to Photos"); progress = 1; changed()
    work = Task { [weak self] in
      do {
        let tracks = try await AVURLAsset(url: file).loadTracks(withMediaType: .video)
        guard let self, self.generation == epoch, !Task.isCancelled else { return }
        guard !tracks.isEmpty else { self.fail(AppText.text("No supported video track. You can save the file to Files.")); return }
        PHPhotoLibrary.shared().performChanges {
          PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: file, options: nil)
        } completionHandler: { [weak self] success, _ in
          Task { @MainActor in
            guard let self, self.generation == epoch else { return }
            if success {
              self.phase = .saved; self.message = AppText.text("Saved to Photos"); self.progress = 1
              self.setResumeData(nil); self.context = nil; self.changed()
              UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else { self.fail(AppText.text("Photos could not import this format. Save the downloaded file to Files.")) }
            self.work = nil
          }
        }
      } catch {
        guard let self, self.generation == epoch else { return }
        self.fail(AppText.text("This file cannot be imported as a video. You can save it to Files."))
      }
    }
  }
  private func fail(_ message: String) { self.message = message; phase = .failed; changed() }
  func pause() {
    guard canPause else { return }
    if let transfer { phase = .pausing; message = AppText.text("Saving breakpoint"); changed(); transfer.pause() }
    else {
      generation += 1; resolver?.cancel(); resolver = nil
      phase = .paused; message = AppText.text("Paused"); changed()
    }
  }
  func cancel() {
    guard canCancel else { return }
    generation += 1; resolver?.cancel(); resolver = nil
    transfer?.cancel(); transfer = nil; work?.cancel(); work = nil
    setResumeData(nil); removeFile(); phase = .cancelled; message = AppText.text("Canceled"); progress = nil; context = nil; changed()
  }
  private func setResumeData(_ data: Data?) {
    resumeData = data
    do { try VideoDownloadStore.setResumeData(data, id: id) }
    catch { VideoDownloadManager.shared.storageError = AppText.text("Could not save the download breakpoint. Keep the app open and check free space.") }
  }
  private func removeFile() {
    if let exportFile { VideoDownloadStore.removeFile(exportFile); self.exportFile = nil }
  }
  func removeExportCopy() { removeFile() }
  func discard() { cancel(); setResumeData(nil); removeFile() }
  private func changed(persist: Bool = true) { VideoDownloadManager.shared.changed(persist: persist) }
}
