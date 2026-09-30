import SwiftUI

struct FloatingDownloads: View {
  @ObservedObject var manager: VideoDownloadManager
  @ObservedObject var gofile: GofileDownloadManager
  @ObservedObject var hosted: HostedDownloadManager
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var activeCount: Int { manager.active.count + gofile.active.count + hosted.active.count }
  private var unfinishedCount: Int { manager.unfinished.count + gofile.unfinished.count + hosted.unfinished.count }
  var body: some View {
    if !manager.items.isEmpty || !gofile.items.isEmpty || !hosted.items.isEmpty {
      Button { manager.showingManager = true } label: {
        ZStack {
          Circle().stroke(.primary.opacity(0.12), lineWidth: 2.5)
          if gofile.active.isEmpty, hosted.active.isEmpty, let fraction = manager.progress, !manager.active.isEmpty {
            Circle().trim(from: 0, to: fraction)
              .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
              .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
            Text("\(Int(fraction * 100))").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
              .contentTransition(.numericText())
          } else if activeCount > 0 { ProgressView().controlSize(.small) }
          else {
            Image(systemName: unfinishedCount == 0 ? "checkmark" : "arrow.down.to.line")
              .font(.system(size: 18, weight: .semibold))
          }
        }.frame(width: 35, height: 35).padding(10)
          .overlay(alignment: .topLeading) {
            if unfinishedCount > 1 {
              Text("\(unfinishedCount)").font(.system(size: 10, weight: .bold)).monospacedDigit()
                .padding(5).background(.blue, in: Circle()).foregroundStyle(.white).offset(x: -3, y: -3)
            }
          }
      }.buttonStyle(.glass).buttonBorderShape(.circle)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: unfinishedCount)
        .accessibilityLabel("Downloads")
        .accessibilityValue("\(activeCount) active, \(unfinishedCount) unfinished")
        .padding(.trailing, 10)
        .transition(.scale.combined(with: .opacity))
    }
  }
}

struct DownloadsView: View {
  @ObservedObject var manager: VideoDownloadManager
  @ObservedObject var gofile: GofileDownloadManager
  @ObservedObject var hosted: HostedDownloadManager
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        if let message = manager.storageError {
          Section { Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.secondary) }
        }
        if manager.items.isEmpty && gofile.items.isEmpty && hosted.items.isEmpty {
          ContentUnavailableView("No downloads", systemImage: "arrow.down.to.line")
        }
        if !manager.items.isEmpty {
          Section("Videos") {
            ForEach(manager.items.reversed()) { VideoDownloadRow(download: $0, manager: manager) }
          }
        }
        if !gofile.items.isEmpty {
          Section("Gofile") {
            ForEach(gofile.items.reversed()) { GofileBatchRow(batch: $0, manager: gofile) }
          }
        }
        if !hosted.items.isEmpty {
          Section("File hosts") { ForEach(hosted.items.reversed()) { HostedBatchRow(batch: $0) } }
        }
      }.navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() } }
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Pause all", systemImage: "pause") { manager.pauseAll(); gofile.pauseAll(); hosted.pauseAll() }
              .disabled(!manager.items.contains(where: \.canPause) && gofile.active.isEmpty && hosted.active.isEmpty)
            Button("Continue all", systemImage: "play") { manager.resumeAll(); gofile.resumeAll(); hosted.resumeAll() }
              .disabled(!manager.items.contains(where: \.canResume) && gofile.resumable.isEmpty && hosted.resumable.isEmpty)
            InfoButton(title: "Downloads", message: DownloadHelp.overview)
            Button("Clear", systemImage: "checkmark.circle") { manager.clearFinished(); gofile.clearFinished(); hosted.clearFinished() }
              .accessibilityLabel("Clear finished downloads")
          }
        }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}

private struct VideoDownloadRow: View {
  @ObservedObject var download: VideoDownload
  @ObservedObject var manager: VideoDownloadManager
  @State private var export: GofileLocalFile?
  @State private var reopen: MediaViewerItem?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(systemName: download.phase == .saved ? "checkmark.circle.fill" : "video").foregroundStyle(.blue)
        Text("Video").font(.headline)
        Spacer()
        Text(download.created, format: .dateTime.month().day().hour().minute().second()).font(.caption).foregroundStyle(.secondary)
      }
      if download.phase == .paused {
        HStack {
          Text("Paused").font(.subheadline).foregroundStyle(.secondary)
          Spacer()
          if !download.message.isEmpty && download.message != "Paused" {
            InfoButton(title: "Resume download", message: download.message)
          }
        }
      } else {
        Text(download.message).font(.subheadline).foregroundStyle(download.phase == .failed ? .red : .secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if download.busy || download.phase == .paused || download.phase == .failed {
        if let progress = download.progress {
          ProgressView(value: progress)
          HStack {
            Text(bytes)
            Spacer()
            Text("\(Int(progress * 100))%").monospacedDigit()
          }.font(.caption).foregroundStyle(.secondary)
        } else if download.busy { ProgressView() }
        HStack(spacing: 12) {
          if download.canPause { Button("Pause", systemImage: "pause") { download.pause() } }
          if download.canResume { Button(download.phase == .failed ? "Retry" : "Continue", systemImage: "play") { download.resume() } }
          if download.canCancel { Button("Cancel", systemImage: "xmark", role: .destructive) { download.cancel() } }
        }.buttonStyle(.glass).labelStyle(.iconOnly)
      }
      if let file = download.exportFile {
        Button("Save to Files", systemImage: "square.and.arrow.up") { export = GofileLocalFile(url: file) }.font(.subheadline)
      }
      if download.phase == .failed, let context = download.context {
        Button("Reopen video", systemImage: "play.rectangle") { reopen = .video(download.source, context.direct, context.referer) }.font(.subheadline)
      }
    }.padding(.vertical, 6)
      .swipeActions { if !download.busy { Button("Remove", role: .destructive) { manager.remove(download) } } }
      .sheet(item: $export) { GofileExport(file: $0.url) }
      .navigationDestination(item: $reopen) { MediaViewerDestination(item: $0) }
  }
  private var bytes: String {
    let received = ByteCountFormatter.string(fromByteCount: download.received, countStyle: .file)
    return download.expected > 0 ? "\(received) / \(ByteCountFormatter.string(fromByteCount: download.expected, countStyle: .file))" : received
  }
}

enum DownloadHelp {
  static let overview = """
  Downloads continue while you browse the app. Switching apps or locking the screen pauses them.

  Previously active videos resume when you return. File-host batches need Continue; the current file restarts.

  Videos save to Photos. File-host batches save to Files. Quitting the app clears unfinished file-host queues, but keeps saved files.
  """
  static let gofile = """
  Downloads continue after you close this page. Reopen them from the floating download button.

  Switching apps or locking the screen pauses the batch. Continue restarts the current file; saved files are kept.

  Quitting the app clears unfinished Gofile queues.
  """
}
