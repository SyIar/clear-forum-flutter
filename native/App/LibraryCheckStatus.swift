import ForumUI
import SwiftUI

struct LibraryCheckProgress {
  var running = false
  var total = 0
  var completed = 0
  var updated = 0
  var failed = 0
  var finishedAt: Date?
  var skippedFresh = false
  var currentTitle: String?
}

struct LibraryCheckStatus: View {
  @ObservedObject var library: LibraryStore
  var compact = false
  private var recentCheck: Date? {
    (library.document.threads.values.compactMap(\.checkedAt) + library.document.following.compactMap(\.checkedAt) + library.document.readingBooks.compactMap(\.checkedAt)).max()
  }
  var body: some View {
    let state = library.checkProgress
    if compact || state.running || state.finishedAt != nil || recentCheck != nil || library.refreshMessage != nil || state.skippedFresh {
      VStack(alignment: .leading, spacing: compact ? 12 : 4) {
        if state.running {
          HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(AppText.format("Checking %@/%@", String(min(state.total, state.completed + 1)), String(state.total)))
          }
          if compact, let title = state.currentTitle {
            Text(title).forumFont(.subheadline).foregroundStyle(.primary).lineLimit(2)
          }
        } else if state.skippedFresh {
          Text(AppText.text("Checked within the last hour. No items need refreshing."))
        } else if state.finishedAt != nil {
          Text(AppText.format("%@ updated · %@ failed", String(state.updated), String(state.failed)))
        } else if compact, recentCheck == nil, library.refreshMessage == nil {
          Text(AppText.text("No update checks yet"))
        }
        if let date = recentCheck, !state.running {
          HStack(spacing: 4) { Text(AppText.text("Last checked")); Text(date, style: .relative) }
        }
        if let message = library.refreshMessage, !state.running,
           !compact || state.failed > 0 || (state.finishedAt == nil && !state.skippedFresh) {
          Text(message).lineLimit(3)
        }
        if compact { Divider() }
        Toggle(AppText.text("Updates only"), isOn: $library.onlyUpdates).toggleStyle(.switch).disabled(state.running)
      }.appFont(.caption).foregroundStyle(.secondary).textCase(nil)
    }
  }
}

struct LibraryUpdateButton: View {
  @ObservedObject var library: LibraryStore
  let refresh: () -> Void
  @State private var showingStatus = false
  private var state: LibraryCheckProgress { library.checkProgress }
  private var symbol: String {
    state.failed > 0 ? "exclamationmark.triangle" : library.onlyUpdates ? "line.3.horizontal.decrease" : "arrow.clockwise"
  }
  var body: some View {
    Button { showingStatus.toggle() } label: {
      Group {
        if state.running { ProgressView().controlSize(.small) }
        else { Image(forumSymbol: symbol, size: 19).foregroundStyle(state.failed > 0 ? Color.orange : .blue) }
      }.frame(width: 44, height: 44)
    }.buttonStyle(.glass).buttonBorderShape(.circle)
      .accessibilityLabel(AppText.text("Update status and filters"))
      .accessibilityValue(state.running ? AppText.text("Checking for updates") : library.onlyUpdates ? AppText.text("Updates only") : "")
      .popover(isPresented: $showingStatus, arrowEdge: .bottom) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text(AppText.text("Update status")).appFont(.headline)
            Spacer(minLength: 12)
            Button { showingStatus = false } label: {
              Image(forumSymbol: "xmark", size: 15).frame(width: 32, height: 32)
            }.buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel(AppText.text("Close"))
          }
          LibraryCheckStatus(library: library, compact: true)
          Button(action: refresh) {
            Label(AppText.text("Refresh"), forumSymbol: "arrow.clockwise")
              .appFont(.subheadline).frame(maxWidth: .infinity, minHeight: 32)
          }.buttonStyle(.glass)
            .disabled(state.running || library.refreshing || !library.document.hasRefreshTargets)
            .accessibilityLabel(AppText.text("Refresh thread and author updates"))
        }.padding(16).frame(width: 288)
          .presentationCompactAdaptation(.popover)
          .presentationBackground(.regularMaterial)
      }
      .onDisappear { showingStatus = false }
  }
}
