import Foundation
import Combine
import ImageIO

@MainActor
final class SouthOfflineStore: ObservableObject {
  static let shared = SouthOfflineStore()
  let repository = SouthOfflineRepository()
  @Published private(set) var entries: [SouthOfflineThread] = []
  @Published private(set) var activeThread: String?
  @Published private(set) var progress = ""
  @Published var error: String?
  private var revision = 0
  private var worker: Task<Void, Never>?
  private var transfer: MediaFileTransfer?
  private var transferID: UUID?
  private var session: ForumSession?
  private var paused = false
  private var seeds: [String: ForumPage] = [:]

  func entry(_ url: URL) -> SouthOfflineThread? { entries.first { $0.id == SouthSitePolicy.threadKey(url) } }
  private func apply(_ snapshot: SouthOfflineRepository.Snapshot) {
    guard snapshot.revision > revision else { return }
    revision = snapshot.revision; entries = snapshot.entries
  }
  func resume(session: ForumSession) async {
    guard session.site == .south, session.offlineThreadID == nil else { return }
    self.session = session; paused = false
    do { apply(try await repository.snapshot()); start() }
    catch { self.error = AppText.error(error) }
  }
  func download(url: URL, title: String, page: ForumPage? = nil, session: ForumSession) {
    guard session.site == .south, session.offlineThreadID == nil else { return }
    self.session = session; paused = false
    if let page, SouthSitePolicy.authorID(page.url) == nil, let id = SouthSitePolicy.threadKey(page.url) { seeds[id] = page }
    Task {
      do { apply(try await repository.enqueue(url: url, title: title)); start() }
      catch { self.error = AppText.error(error) }
    }
  }
  func pause() { paused = true; worker?.cancel(); transfer?.cancel() }
  func remove(_ entry: SouthOfflineThread) async {
    if activeThread == entry.id { worker?.cancel(); transfer?.cancel() }
    seeds.removeValue(forKey: entry.id)
    do { apply(try await repository.remove(entry.token)) }
    catch { self.error = AppText.error(error) }
  }
  private func start() {
    guard worker == nil, !paused, let session, entries.contains(where: { $0.state == .pending }) else { return }
    worker = Task { [weak self] in
      guard let self else { return }
      defer { self.activeThread = nil; self.progress = ""; self.worker = nil; self.start() }
      while !Task.isCancelled, !self.paused, let entry = self.entries.last(where: { $0.state == .pending }) {
        self.activeThread = entry.id
        var missing = Set<URL>()
        do {
          var number = 1
          while let current = self.entries.first(where: { $0.token == entry.token }), number <= current.totalPages {
            try Task.checkCancellation()
            self.progress = AppText.format("Saving page %@ of %@", String(number), String(current.totalPages))
            guard let target = SouthSitePolicy.pageURL(entry.url, number: number) else { throw ReaderFailure.unsupported }
            let cached = try await self.repository.page(target, threadID: entry.id, normalizeNavigation: false)
            let page: ForumPage
            if let cached {
              page = cached
            } else {
              let fresh = try await session.load(target)
              if let seed = self.seeds[entry.id], seed.pageNumber == number {
                page = fresh.preservingPurchaseContent(from: seed)
              } else { page = fresh }
              self.apply(try await self.repository.store(page, token: entry.token, expectedPage: number))
            }
            let images = SouthOfflineImages.urls(in: page)
            for (index, url) in images.enumerated() {
              try Task.checkCancellation()
              self.progress = AppText.format("Page %@ - image %@/%@", String(number), String(index + 1), String(images.count))
              if try await self.repository.imageFile(url, threadID: entry.id) != nil { missing.remove(url); continue }
              do {
                let file = try await self.downloadImage(url, referer: target)
                defer { try? FileManager.default.removeItem(at: file) }
                let valid = await Task.detached(priority: .utility) {
                  guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                        CGImageSourceGetCount(source) > 0 else { return false }
                  return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil
                }.value
                guard valid else { throw ReaderFailure.unsupported }
                self.apply(try await self.repository.storeImage(file, url: url, token: entry.token))
                missing.remove(url)
              } catch {
                try Task.checkCancellation()
                if error as? ReaderFailure == .storage { throw error }
                missing.insert(url)
              }
            }
            number += 1
            try await Task.sleep(for: .milliseconds(250))
          }
          self.apply(try await self.repository.finish(entry.token, missingImages: missing.count))
          self.seeds.removeValue(forKey: entry.id)
        } catch {
          if Task.isCancelled { return }
          do { self.apply(try await self.repository.finish(entry.token, missingImages: missing.count, failure: AppText.error(error))) }
          catch { self.error = AppText.error(error); self.paused = true; return }
        }
      }
    }
  }
  private func downloadImage(_ url: URL, referer: URL) async throws -> URL {
    let id = UUID()
    return try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        let transfer = MediaFileTransfer(limit: MediaFilePolicy.imageLimit, referer: referer, progress: { _ in }) { result in
          continuation.resume(with: result)
        }
        self.transferID = id; self.transfer = transfer
        transfer.start(url)
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard self?.transferID == id else { return }
        self?.transfer?.cancel()
      }
    }
  }
}
