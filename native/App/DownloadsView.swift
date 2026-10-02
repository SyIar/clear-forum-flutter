import ForumUI
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
            Image(forumSymbol: unfinishedCount == 0 ? "checkmark" : "arrow.down.to.line")
              .font(.system(size: 18, weight: .semibold))
          }
        }.frame(width: 35, height: 35).padding(10)
      }.buttonStyle(.glass).buttonBorderShape(.circle)
        // Keep the badge outside the button style's circular glass mask.
        .overlay(alignment: .topLeading) {
          if unfinishedCount > 1 {
            Text("\(unfinishedCount)").font(.system(size: 10, weight: .bold)).monospacedDigit()
              .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20).fixedSize()
              .background(.blue, in: Capsule()).foregroundStyle(.white)
              .offset(x: -3, y: -3).zIndex(1)
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
        .padding(6)
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: unfinishedCount)
        .accessibilityLabel(AppText.text("Downloads"))
        .accessibilityValue(AppText.format("%@ active, %@ unfinished", String(describing: activeCount), String(describing: unfinishedCount)))
        .padding(.trailing, 10)
        .transition(.scale.combined(with: .opacity))
    }
  }
}

struct DownloadsView: View {
  @ObservedObject var manager: VideoDownloadManager
  @ObservedObject var gofile: GofileDownloadManager
  @ObservedObject var hosted: HostedDownloadManager
  @Environment(\.dismiss) private var nativeDismiss
  @Environment(\.forumDismiss) private var forumDismiss
  private func dismiss() { if forumDismiss.available { forumDismiss() } else { nativeDismiss() } }
  @State private var selected = DownloadGroup.active
  private var tasks: [DownloadTaskRow] {
    (manager.items.map(DownloadTaskRow.video) + gofile.items.map(DownloadTaskRow.gofile) + hosted.items.map(DownloadTaskRow.hosted))
      .sorted { $0.created > $1.created }
  }
  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker(AppText.text("Download status"), selection: $selected) {
            ForEach(DownloadGroup.allCases) { group in
              Text(AppText.text(group.rawValue) + " (\(tasks.filter { $0.group == group }.count))").tag(group)
            }
          }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
        ForEach([manager.storageError, gofile.storageError, hosted.storageError].compactMap { $0 }, id: \.self) { message in
          Label(message, forumSymbol: "exclamationmark.triangle").appFont(.subheadline).foregroundStyle(.secondary)
        }
        if tasks.filter({ $0.group == selected }).isEmpty {
          ForumUnavailableView(AppText.text("No downloads in this group"), forumSymbol: "arrow.down.to.line")
        }
        ForEach(tasks.filter { $0.group == selected }) { task in
          switch task {
          case .video(let item): VideoDownloadRow(download: item, manager: manager)
          case .gofile(let item): GofileBatchRow(batch: item, manager: gofile)
          case .hosted(let item): HostedBatchRow(batch: item)
          }
        }
      }.navigationTitle(AppText.text("Downloads")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) { Button(AppText.text("Close"), forumSymbol: "xmark") { dismiss() } }
          ToolbarItemGroup(placement: .topBarTrailing) {
            DownloadToolbarButton(title: AppText.text("Pause all"), symbol: "pause.toolbar") { manager.pauseAll(); gofile.pauseAll(); hosted.pauseAll() }
              .disabled(!manager.items.contains(where: \.canPause) && gofile.active.isEmpty && hosted.active.isEmpty)
            DownloadToolbarButton(title: AppText.text("Continue all"), symbol: "play.toolbar") { manager.resumeAll(); gofile.resumeAll(); hosted.resumeAll() }
              .disabled(!manager.items.contains(where: \.canResume) && gofile.resumable.isEmpty && hosted.resumable.isEmpty)
            InfoButton(title: AppText.text("Downloads"), message: DownloadHelp.overview, iconSize: 22).tint(.primary)
            DownloadToolbarButton(title: AppText.text("Clear finished downloads"), symbol: "broom") { manager.clearFinished(); gofile.clearFinished(); hosted.clearFinished() }
              .disabled(!manager.items.contains(where: { $0.phase == .saved || $0.phase == .cancelled }) && gofile.finished.isEmpty && !hosted.items.contains(where: \.finished))
          }
        }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}

private struct DownloadToolbarButton: View {
  let title: String
  let symbol: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      ForumToolbarIcon(symbol)
    }.buttonStyle(.borderless).tint(.primary).accessibilityLabel(title)
  }
}

private struct VideoDownloadRow: View {
  @ObservedObject var download: VideoDownload
  @ObservedObject var manager: VideoDownloadManager
  @State private var export: GofileLocalFile?
  @State private var reopen: MediaViewerItem?
  @State private var preview: GofileLocalFile?
  @State private var website: URL?
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Image(forumSymbol: download.phase == .saved ? "checkmark.circle.fill" : "video").foregroundStyle(.blue)
        Text(download.displayName).appFont(.headline).lineLimit(2)
        Spacer()
        Text(download.created, format: .dateTime.month().day().hour().minute().second()).appFont(.caption).foregroundStyle(.secondary)
      }
      if download.phase == .paused {
        HStack {
          Text(AppText.text("Paused")).appFont(.subheadline).foregroundStyle(.secondary)
          Spacer()
          if !download.message.isEmpty && download.message != AppText.text("Paused") {
            InfoButton(title: AppText.text("Resume download"), message: download.message)
          }
        }
      } else {
        Text(download.message).appFont(.subheadline).foregroundStyle(download.phase == .failed ? .red : .secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if download.busy || download.phase == .paused || download.phase == .failed {
        if let progress = download.progress {
          ProgressView(value: progress)
          HStack {
            Text(bytes)
            Spacer()
            Text("\(Int(progress * 100))%").monospacedDigit()
          }.appFont(.caption).foregroundStyle(.secondary)
        } else if download.busy { ProgressView() }
        HStack(spacing: 12) {
          if download.canPause { Button(AppText.text("Pause"), forumSymbol: "pause") { download.pause() } }
          if download.canResume { Button(download.phase == .failed ? AppText.text("Retry") : AppText.text("Continue"), forumSymbol: "play") { download.resume() } }
          if download.canCancel { Button(AppText.text("Cancel"), forumSymbol: "xmark", role: .destructive) { download.cancel() } }
        }.buttonStyle(.glass).labelStyle(.iconOnly)
      }
      if let file = download.exportFile {
        HStack(spacing: 16) {
          Button(AppText.text("Preview"), forumSymbol: "play.circle") { preview = GofileLocalFile(url: file) }
          ShareLink(item: file) { Label(AppText.text("Share"), forumSymbol: "square.and.arrow.up") }
          Button(AppText.text("Save to Files"), forumSymbol: "folder") { export = GofileLocalFile(url: file) }
        }.appFont(.subheadline).labelStyle(.iconOnly)
      }
      if let origin = download.origin {
        Button(AppText.text("Source thread"), forumSymbol: "arrow.up.right") { website = origin.page }.appFont(.caption)
      }
      if download.phase == .failed, let context = download.context {
        Button(AppText.text("Reopen video"), forumSymbol: "play.rectangle") { reopen = .video(download.source, context.direct, context.referer) }.appFont(.subheadline)
      }
    }.padding(.vertical, 6)
      .swipeActions { if !download.busy { Button(AppText.text("Remove"), role: .destructive) { manager.remove(download) } } }
      .sheet(item: $export) { GofileExport(file: $0.url) }
      .navigationDestination(item: $preview) { GofileQuickLook(file: $0.url).navigationTitle(download.displayName) }
      .background { ExternalBrowserPresenter(url: $website).frame(width: 0, height: 0) }
      .navigationDestination(item: $reopen) { MediaViewerDestination(item: $0) }
  }
  private var bytes: String {
    let received = ByteCountFormatter.string(fromByteCount: download.received, countStyle: .file)
    return download.expected > 0 ? "\(received) / \(ByteCountFormatter.string(fromByteCount: download.expected, countStyle: .file))" : received
  }
}

private enum DownloadGroup: String, CaseIterable, Identifiable {
  case active = "In progress", attention = "Needs attention", completed = "Completed"
  var id: String { rawValue }
}

@MainActor private enum DownloadTaskRow: Identifiable {
  case video(VideoDownload), gofile(GofileBatchDownload), hosted(HostedBatchDownload)
  var id: UUID { switch self { case .video(let item): return item.id; case .gofile(let item): return item.id; case .hosted(let item): return item.id } }
  var created: Date { switch self { case .video(let item): return item.created; case .gofile(let item): return item.created; case .hosted(let item): return item.created } }
  var group: DownloadGroup {
    switch self {
    case .video(let item): return [.saved, .cancelled].contains(item.phase) ? .completed : item.busy ? .active : .attention
    case .gofile(let item): return [.finished, .cancelled].contains(item.phase) ? .completed : item.running ? .active : .attention
    case .hosted(let item): return item.finished ? .completed : item.running ? .active : .attention
    }
  }
}

enum DownloadHelp {
  static let overview = AppText.text("Download queues and saved files survive app restarts. Continue resumes a supported breakpoint; expired connections may restart the current file.\n\nFile-host transfers can finish the current file in the background. Folder discovery and the next file wait until you return. Force-quitting stops background transfers. Videos pause safely and resume when you return.\n\nVideos save to Photos; up to three recent originals (1 GB total) remain available for preview and export. Clearing finished history removes these extra copies, not Photos or files saved in Documents.")
  static let gofile = AppText.text("Closing this page keeps downloads running. Queues survive app restarts; use Continue to resume. The current file can finish in the background, while folder discovery waits until you return. Resume support depends on the server. Saved files remain in Files.")
}
