import ForumUI
import SwiftUI
import UIKit

@MainActor final class LocalArchiveManager: ObservableObject {
  static let shared = LocalArchiveManager()
  struct Job {
    let id = UUID()
    let progress = Progress(totalUnitCount: 1)
    var running = true
    var folder: [String]?
    var error: String?
    var needsPassword = false
  }
  @Published private(set) var jobs: [URL: Job] = [:]
  var running: Bool { jobs.values.contains(where: \.running) }
  var activeFiles: [URL] { jobs.filter { $0.value.running }.map(\.key) }

  func start(_ file: URL, password: String? = nil) {
    guard !running else { return }
    jobs = jobs.filter { $0.value.running || $0.key == file }
    let job = Job()
    jobs[file] = job
    let progress = job.progress
    let background = UIApplication.shared.beginBackgroundTask(withName: "Local ZIP extraction") { progress.cancel() }
    Task {
      defer {
        jobs[file]?.running = false
        if background != .invalid { UIApplication.shared.endBackgroundTask(background) }
      }
      do {
        let root = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let catalog = LocalFileCatalog(root: root)
        let rawRoot = root.standardizedFileURL
        let base = file.standardizedFileURL.path.hasPrefix(rawRoot.path + "/") ? rawRoot : catalog.root
        guard file.isFileURL, file.standardizedFileURL.path.hasPrefix(base.path + "/") else { throw LocalFileCatalog.Failure.unavailable }
        let path = Array(file.standardizedFileURL.pathComponents.dropFirst(base.pathComponents.count))
        let worker = Task.detached(priority: .utility) { try LocalArchiveExtractor.extract(path, in: catalog, progress: progress, password: password) }
        let folder = try await worker.value
        jobs[file]?.folder = folder
        NotificationCenter.default.post(name: FileDownloadStore.didInstallFile, object: nil)
      } catch is CancellationError {
        jobs[file]?.error = AppText.text("Canceled")
      } catch LocalArchiveExtractor.Failure.passwordRequired {
        jobs[file]?.needsPassword = true
        jobs[file]?.error = AppText.text("This ZIP needs a password. Enter it to extract the files.")
      } catch LocalArchiveExtractor.Failure.incorrectPassword {
        jobs[file]?.needsPassword = true
        jobs[file]?.error = AppText.text("The password is incorrect or the encrypted data is damaged. Check the password and try again.")
      } catch LocalArchiveExtractor.Failure.insufficientSpace {
        jobs[file]?.error = AppText.text("Not enough free space to extract this ZIP.")
      } catch LocalArchiveExtractor.Failure.tooLarge {
        jobs[file]?.error = AppText.text("This archive exceeds the extraction size or file-count limit.")
      } catch {
        jobs[file]?.error = AppText.text("Cannot extract this ZIP. It may be damaged or use an unsupported format. You can export it to another app.")
      }
    }
  }
  func cancel(_ file: URL) { jobs[file]?.progress.cancel() }
}

private struct ExtractedFolder: Identifiable { let path: [String]; var id: [String] { path } }

struct LocalArchiveView: View {
  let file: URL
  @ObservedObject private var manager = LocalArchiveManager.shared
  @State private var fraction = 0.0
  @State private var folder: ExtractedFolder?
  @State private var visible = false
  @State private var export: GofileLocalFile?
  @State private var password = ""
  @FocusState private var passwordFocused: Bool
  private var job: LocalArchiveManager.Job? { manager.jobs[file] }

  var body: some View {
    List {
      Section {
        Label(file.lastPathComponent, forumSymbol: "folder").appFont(.headline)
        Text(AppText.text("Extract beside the ZIP into a new folder. Existing files and the original ZIP are kept."))
          .appFont(.subheadline).foregroundStyle(.secondary)
      }
      Section {
        if job?.running == true {
          HStack {
            Text(AppText.text("Extracting ZIP"))
            Spacer()
            Text("\(Int(fraction * 100))%").monospacedDigit()
          }
          ProgressView(value: fraction)
          Button(AppText.text("Cancel"), forumSymbol: "xmark") { manager.cancel(file) }
        } else {
          if let error = job?.error { Text(error).foregroundStyle(.secondary) }
          if let path = job?.folder {
            Button(AppText.text("Open extracted folder"), forumSymbol: "folder") { folder = ExtractedFolder(path: path) }
          }
          if job?.needsPassword == true {
            SecureField(AppText.text("ZIP password"), text: $password)
              .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
              .focused($passwordFocused).submitLabel(.go).onSubmit { start() }
            Text(AppText.text("The password is used only for this extraction and is not saved."))
              .appFont(.caption).foregroundStyle(.secondary)
          }
          Button(AppText.text("Extract ZIP"), forumSymbol: "square.and.arrow.down") { start() }
            .disabled(manager.running)
          if manager.running { Text(AppText.text("Another ZIP is being extracted. Please wait.")).appFont(.caption).foregroundStyle(.secondary) }
        }
      }
      Section {
        Button(AppText.text("Save to Files"), forumSymbol: "folder") { export = GofileLocalFile(url: file) }
        ShareLink(item: file) { Label(AppText.text("Share"), forumSymbol: "square.and.arrow.up") }
      }
    }.appFont(.body)
      .onAppear { visible = true }.onDisappear { visible = false; password = ""; passwordFocused = false }
      .onChange(of: job?.needsPassword) { _, needsPassword in
        if visible, needsPassword == true { passwordFocused = true }
      }
      .onChange(of: job?.folder) { _, path in
        if visible, let path { folder = ExtractedFolder(path: path) }
      }
      .task(id: job?.id) {
        fraction = job?.progress.fractionCompleted ?? 0
        while !Task.isCancelled, let job = manager.jobs[file], job.running {
          fraction = min(1, max(0, job.progress.fractionCompleted))
          do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
        }
      }
      .forumSheet(item: $folder) { folder in
        NavigationStack { LocalFilesView(path: folder.path) }
      }
      .sheet(item: $export) { GofileExport(file: $0.url) }
  }
  private func start() {
    guard !manager.running else { return }
    let supplied = job?.needsPassword == true ? password : nil
    password = ""; passwordFocused = false
    manager.start(file, password: supplied)
  }
}
