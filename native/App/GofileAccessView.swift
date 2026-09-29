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
      Label(failure.title, systemImage: failure.symbol).font(.headline)
      Text(failure.localizedDescription).font(.subheadline).foregroundStyle(.secondary)
      if failure.needsPassword {
        SecureField("Password", text: $password).textContentType(.password)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
          .textFieldStyle(.roundedBorder).disabled(busy)
        Button {
          let value = password; password = ""
          Task { await unlock(value) }
        } label: {
          HStack { if busy { ProgressView() }; Text("Unlock") }
        }.buttonStyle(.glassProminent).disabled(password.isEmpty || busy)
      } else if let date = failure.retryDate {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          if context.date < date {
            Text("Try again in \(Int(ceil(date.timeIntervalSince(context.date))))s").font(.caption).monospacedDigit()
          } else { Button("Try again", systemImage: "arrow.clockwise", action: retry).disabled(busy) }
        }
      } else {
        Button("Try again", systemImage: "arrow.clockwise", action: retry).disabled(busy)
      }
      Button("Open website", systemImage: "globe", action: website).font(.subheadline).disabled(busy)
    }.padding(.vertical, 8)
  }
}

struct GofileBatchView: View {
  @ObservedObject var batch: GofileBatchDownload
  @ObservedObject private var session: GofileSession
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dismiss) private var dismiss
  @State private var export: GofileLocalFile?
  init(batch: GofileBatchDownload) { self.batch = batch; self.session = batch.session }
  var body: some View {
    NavigationStack {
      List {
        Section {
          Label(title, systemImage: batch.phase == .finished ? "checkmark.circle" : "arrow.down.doc")
            .font(.headline)
          Text("\(batch.completed) saved · \(batch.skipped.count) skipped · \(batch.pending) pending")
            .font(.subheadline).foregroundStyle(.secondary)
          Text("Includes every item on this page and all pages inside its subfolders.").font(.caption).foregroundStyle(.secondary)
          if !batch.current.isEmpty { Text(batch.current).font(.subheadline).lineLimit(3) }
          if batch.running {
            if let progress = batch.progress {
              ProgressView(value: progress)
              Text("\(Int(progress * 100))%").font(.caption).monospacedDigit()
            } else { ProgressView() }
            Button("Pause", systemImage: "pause", action: batch.pause)
          } else if batch.phase == .paused && batch.gate == nil {
            if let issue = batch.issue { Text(issue).font(.subheadline).foregroundStyle(.secondary) }
            Button("Continue", systemImage: "play", action: batch.resume).disabled(!batch.canResume)
          } else if batch.phase == .cancelled, let issue = batch.issue {
            Text(issue).font(.subheadline).foregroundStyle(.secondary)
          }
        }
        if let gate = batch.gate {
          Section {
            GofileAccessView(failure: gate, busy: batch.running, retry: batch.resume,
              unlock: { await batch.unlock($0) }, website: { session.showWebsite() })
          }
        }
        if batch.phase == .paused, batch.pending > 0 {
          Section { Button("Skip this item", systemImage: "forward.end", action: batch.skip) }
        }
        if let directory = batch.directory {
          Section {
            Label("Files are saved in Gofile Downloads", systemImage: "folder")
            Text("Files → On My iPhone → forum lite → Gofile Downloads").font(.caption).foregroundStyle(.secondary)
            Button("Export folder", systemImage: "square.and.arrow.up") { export = GofileLocalFile(url: directory) }
              .disabled(batch.running)
          } footer: {
            Text("Downloads run one at a time while this screen is open. Closing it or leaving the app pauses the queue. Resume while this viewer remains open; saved files remain available after closing the app.")
          }
        }
        if !batch.skipped.isEmpty {
          Section("Skipped items") {
            ForEach(batch.skipped) { item in
              VStack(alignment: .leading, spacing: 4) {
                Text(item.path).font(.subheadline)
                Text(item.reason).font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        if batch.phase == .running || batch.phase == .paused {
          Section { Button("Stop batch", systemImage: "stop", role: .destructive, action: batch.cancel) }
        }
      }.navigationTitle("Download all").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close", systemImage: "xmark") { batch.pause(); dismiss() } } }
        .background {
          if !session.showingWebsite {
            GofileWebSurface(webView: session.webView).frame(width: 1, height: 1).opacity(0).allowsHitTesting(false).accessibilityHidden(true)
          }
        }
        .sheet(isPresented: $session.showingWebsite, onDismiss: { batch.returnFromWebsite() }) {
          NavigationStack {
            GofileWebSurface(webView: session.webView).ignoresSafeArea(.container, edges: .bottom)
              .navigationTitle("gofile.io").navigationBarTitleDisplayMode(.inline)
              .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Files") { session.showingWebsite = false } } }
          }
        }
        .sheet(item: $export) { GofileExport(file: $0.url) }
    }.onChange(of: scenePhase) { _, value in if value != .active { batch.pause() } }
      .onDisappear { batch.pause() }
  }
  private var title: String {
    switch batch.phase {
    case .idle: return "Preparing downloads"
    case .running: return "Downloading one at a time"
    case .paused: return "Paused"
    case .finished: return batch.skipped.isEmpty ? "All files saved" : "Finished with skipped items"
    case .cancelled: return "Stopped · Saved files kept"
    }
  }
}
