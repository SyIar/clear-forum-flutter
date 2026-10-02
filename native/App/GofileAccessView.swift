import ForumUI
import SwiftUI

struct GofileAccessView: View {
  let failure: GofileFailure
  let busy: Bool
  let retry: () -> Void
  let unlock: (String) async -> Void
  let website: () -> Void
  @State private var password = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label(failure.title, forumSymbol: failure.symbol).appFont(.headline)
      Text(failure.localizedDescription).appFont(.subheadline).foregroundStyle(.secondary)
      if failure.needsPassword {
        SecureField(AppText.text("Password"), text: $password).textContentType(.password)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .textFieldStyle(.roundedBorder).disabled(busy)
        Button {
          let value = password; password = ""
          Task { await unlock(value) }
        } label: {
          HStack { if busy { ProgressView() }; Text(AppText.text("Unlock")) }
        }.buttonStyle(.glassProminent).disabled(password.isEmpty || busy)
      } else if let date = failure.retryDate {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          if context.date < date {
            Text(AppText.format("Try again in %@s", String(describing: Int(ceil(date.timeIntervalSince(context.date)))))).appFont(.caption).monospacedDigit()
          } else { Button(AppText.text("Try again"), forumSymbol: "arrow.clockwise", action: retry).disabled(busy) }
        }
      } else {
        Button(AppText.text("Try again"), forumSymbol: "arrow.clockwise", action: retry).disabled(busy)
      }
      Button(AppText.text("Open website"), forumSymbol: "globe", action: website).appFont(.subheadline).disabled(busy)
    }.padding(.vertical, 8)
  }
}

struct GofileBatchView: View {
  @ObservedObject var batch: GofileBatchDownload
  @ObservedObject private var session: GofileSession
  @State private var export: GofileLocalFile?
  @State private var preview: GofileLocalFile?
  init(batch: GofileBatchDownload) { self.batch = batch; self.session = batch.session }
  var body: some View {
    List {
      Section {
        Label(title, forumSymbol: batch.phase == .finished ? "checkmark.circle" : "arrow.down.doc")
          .appFont(.headline)
        Text(AppText.format("%@ saved · %@ skipped · %@ queued", String(describing: batch.completed), String(describing: batch.skipped.count), String(describing: batch.queued)))
          .appFont(.subheadline).foregroundStyle(.secondary)
        if !batch.current.isEmpty { Text(batch.current).appFont(.subheadline).lineLimit(3) }
        if batch.running {
          Text(batch.activityText).appFont(.caption).foregroundStyle(.secondary)
          if let progress = batch.progress {
            ProgressView(value: progress)
            Text("\(Int(progress * 100))%").appFont(.caption).monospacedDigit()
          } else { ProgressView() }
          Button(AppText.text("Pause"), forumSymbol: "pause", action: batch.pause)
        } else if batch.phase == .paused && batch.gate == nil {
          if let issue = batch.issue { Text(issue).appFont(.subheadline).foregroundStyle(.secondary) }
          Button(AppText.text("Continue"), forumSymbol: "play", action: batch.resume).disabled(!batch.canResume)
        } else if batch.phase == .cancelled, let issue = batch.issue {
          Text(issue).appFont(.subheadline).foregroundStyle(.secondary)
        }
      }
      if let gate = batch.gate {
        Section {
          GofileAccessView(failure: gate, busy: batch.running, retry: batch.resume,
            unlock: { await batch.unlock($0) }, website: { session.showWebsite() })
        }
      }
      if batch.phase == .paused, batch.pending > 0 {
        Section { Button(AppText.text("Skip this item"), forumSymbol: "forward.end", action: batch.skip) }
      }
      if let directory = batch.directory {
        Section {
          HStack {
            Label(AppText.text("Gofile Downloads"), forumSymbol: "folder")
            Spacer()
            InfoButton(title: AppText.text("Saved files"), message: savedFilesInfo)
          }
          Button(AppText.text("Export folder"), forumSymbol: "square.and.arrow.up") { export = GofileLocalFile(url: directory) }
            .disabled(batch.running)
        }
      }
      if !batch.savedFiles.isEmpty {
        Section(AppText.text("Saved files")) {
          ForEach(batch.savedFiles.keys.sorted(), id: \.self) { key in
            if let file = batch.savedFiles[key] {
              HStack(spacing: 12) {
                Button { preview = GofileLocalFile(url: file) } label: {
                  Label(file.lastPathComponent, forumSymbol: "doc").appFont(.subheadline).lineLimit(2)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                ShareLink(item: file) { Image(forumSymbol: "square.and.arrow.up").frame(width: 44, height: 44) }
                  .buttonStyle(.borderless).accessibilityLabel(AppText.text("Share"))
                Button { export = GofileLocalFile(url: file) } label: { Image(forumSymbol: "folder").frame(width: 44, height: 44) }
                  .buttonStyle(.borderless).accessibilityLabel(AppText.text("Save to Files"))
              }
            }
          }
        }
      }
      if !batch.skipped.isEmpty {
        Section(AppText.text("Skipped items")) {
          ForEach(batch.skipped) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.path).appFont(.subheadline)
              Text(item.reason).appFont(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      if batch.phase == .running || batch.phase == .paused {
        Section { Button(AppText.text("Stop batch"), forumSymbol: "stop", role: .destructive, action: batch.cancel) }
      }
    }.navigationTitle(AppText.text("Gofile Helper")).navigationBarTitleDisplayMode(.inline)
      .toolbarRole(.editor)
      .toolbar(.hidden, for: .bottomBar)
      .toolbar { ToolbarItem(placement: .topBarTrailing) { InfoButton(title: AppText.text("Gofile downloads"), message: DownloadHelp.gofile) } }
      .sheet(isPresented: $session.showingWebsite, onDismiss: { batch.returnFromWebsite() }) {
        NavigationStack {
          GofileWebSurface(webView: session.webView).ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle("gofile.io").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(AppText.text("Files")) { session.showingWebsite = false } } }
        }
      }
      .sheet(item: $export) { GofileExport(file: $0.url) }
      .navigationDestination(item: $preview) { GofileQuickLook(file: $0.url).navigationTitle(AppText.text("Preview")) }
  }
  private var title: String {
    switch batch.phase {
    case .idle: return AppText.text("Preparing downloads")
    case .running: return AppText.text("Downloading")
    case .paused: return AppText.text("Paused")
    case .finished: return batch.skipped.isEmpty ? AppText.text("All files saved") : AppText.text("Finished with skipped items")
    case .cancelled: return AppText.text("Stopped")
    }
  }
  private var savedFilesInfo: String {
    let location: String
    if Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool == true,
       Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool == true {
      location = AppText.text("Files → On My iPhone → Forum Lite → Gofile Downloads")
    } else {
      location = AppText.text("Saved in this app. Use Export folder to save a copy in Files.")
    }
    return location + AppText.text("\n\nPause the batch before exporting its folder. Stopping or removing a batch keeps saved files.")
  }
}
