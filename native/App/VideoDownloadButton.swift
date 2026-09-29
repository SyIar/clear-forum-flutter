import SwiftUI

struct VideoDownloadButton: View {
  @ObservedObject var state: MediaViewerState
  @ObservedObject var download: VideoDownload

  var body: some View {
    Button {
      if [.idle, .failed, .cancelled].contains(download.phase), state.downloadReady { state.player?.downloadVideo() }
      else { VideoDownloadManager.shared.showingManager = true }
    } label: {
      DownloadIndicator(phase: download.phase, progress: download.progress)
    }
    .disabled(download.phase == .idle && !state.downloadReady)
    .accessibilityLabel(download.phase == .idle ? "Download video" : "Manage video download")
    .accessibilityValue(download.busy ? progressDescription : "")
  }

  private var progressDescription: String {
    if download.phase == .saving { return "Saving to Photos" }
    if let progress = download.progress, progress.isFinite { return "\(Int((min(1, max(0, progress)) * 100).rounded(.down))) percent downloaded" }
    return "Preparing download"
  }
}

private struct DownloadIndicator: View {
  let phase: VideoDownload.Phase
  let progress: Double?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var fraction: Double? {
    guard let progress, progress.isFinite else { return nil }
    return min(1, max(0, progress))
  }
  var body: some View {
    ZStack {
      switch phase {
      case .queued, .authorizing, .downloading, .pausing, .saving:
        Circle().stroke(.primary.opacity(0.16), lineWidth: 2)
        if let fraction {
          Circle().trim(from: 0, to: fraction)
            .stroke(.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)
          Text("\(Int((fraction * 100).rounded(.down)))")
            .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
        } else {
          // No content length means no honest percentage is available yet.
          ProgressView().controlSize(.mini)
        }
      case .saved: Image(systemName: "checkmark")
      case .paused: Image(systemName: "pause")
      case .idle, .failed, .cancelled: Image(systemName: "arrow.down.to.line")
      }
    }.frame(width: 28, height: 28)
      .foregroundStyle(.primary)
      .accessibilityElement(children: .ignore)
  }
}
