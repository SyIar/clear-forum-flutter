import SwiftUI

struct FloatingVideoDownloads: View {
  @ObservedObject var manager: VideoDownloadManager
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    if !manager.items.isEmpty {
      Button { manager.showingManager = true } label: {
        ZStack {
          Circle().stroke(.primary.opacity(0.12), lineWidth: 2.5)
          if let fraction = manager.progress, !manager.active.isEmpty {
            Circle().trim(from: 0, to: fraction)
              .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
              .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
            Text("\(Int(fraction * 100))").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
              .contentTransition(.numericText())
          } else if !manager.active.isEmpty { ProgressView().controlSize(.small) }
          else {
            Image(systemName: manager.unfinished.isEmpty ? "checkmark" : "arrow.down.to.line")
              .font(.system(size: 18, weight: .semibold))
          }
        }.frame(width: 35, height: 35).padding(10)
          .overlay(alignment: .topLeading) {
            if manager.unfinished.count > 1 {
              Text("\(manager.unfinished.count)").font(.system(size: 10, weight: .bold)).monospacedDigit()
                .padding(5).background(.blue, in: Circle()).foregroundStyle(.white).offset(x: -3, y: -3)
            }
          }
      }.buttonStyle(.glass).buttonBorderShape(.circle)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: manager.unfinished.count)
        .accessibilityLabel("Downloads")
        .accessibilityValue("\(manager.active.count) active, \(manager.unfinished.count) unfinished")
        .padding(.trailing, 10)
        .transition(.scale.combined(with: .opacity))
    }
  }
}

struct VideoDownloadsView: View {
  @ObservedObject var manager: VideoDownloadManager
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      List {
        if let message = manager.storageError {
          Section { Label(message, systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(.secondary) }
        }
        if manager.items.isEmpty { ContentUnavailableView("No downloads", systemImage: "arrow.down.to.line", description: Text("Start a download from a video player.")) }
        if !manager.unfinished.isEmpty {
          Section {
            ForEach(manager.unfinished.reversed()) { VideoDownloadRow(download: $0, manager: manager) }
          } header: { Text("Downloads") } footer: {
            Text("Up to two videos download at once. Leaving the player keeps them running. The app saves a breakpoint when entering the background and continues when you return. Resume support depends on the server.")
          }
        }
        let finished = manager.items.filter { $0.phase == .saved || $0.phase == .cancelled }
        if !finished.isEmpty {
          Section("Finished") { ForEach(finished.reversed()) { VideoDownloadRow(download: $0, manager: manager) } }
        }
      }.navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { dismiss() } }
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Pause all", systemImage: "pause") { manager.pauseAll() }.disabled(!manager.items.contains(where: \.canPause))
            Button("Continue all", systemImage: "play") { manager.resumeAll() }.disabled(!manager.items.contains(where: \.canResume))
            Menu("More", systemImage: "ellipsis") {
              Button("Clear finished", systemImage: "checkmark.circle") { manager.clearFinished() }
            }
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
      Text(download.message).font(.subheadline).foregroundStyle(download.phase == .failed ? .red : .secondary)
        .fixedSize(horizontal: false, vertical: true)
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
