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

struct LibraryUpdateFailure: Identifiable {
  let id: String
  let title: String
  let message: String
}

extension LibraryStore {
  var updateChecksRunning: Bool {
    refreshing || checkProgress.running || bookRefreshPhases.values.contains(.checking) || !refreshingAuthors.isEmpty
  }
  var activeUpdateTitle: String? {
    checkProgress.currentTitle ?? document.readingBooks.first { bookRefreshPhases[$0.id] == .checking }?.title ??
      document.following.first { refreshingAuthors.contains($0.id) }?.name
  }
  var updateFailures: [LibraryUpdateFailure] {
    document.readingBooks.compactMap { book in
      bookErrors[book.id].map { LibraryUpdateFailure(id: book.id, title: book.title, message: $0) }
    } + document.following.compactMap { author in
      authorErrors[author.id].map { LibraryUpdateFailure(id: author.id, title: author.name, message: $0) }
    }
  }
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
        if library.updateChecksRunning {
          HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            if state.running {
              Text(AppText.format("Checking %@/%@", String(min(state.total, state.completed + 1)), String(state.total)))
            } else { Text(AppText.text("Checking for updates")) }
          }
          if compact, let title = library.activeUpdateTitle {
            Text(title).forumFont(.subheadline).foregroundStyle(.primary).lineLimit(2)
          }
        } else if state.skippedFresh {
          Text(AppText.text("Checked within the last hour. No items need refreshing."))
        } else if state.finishedAt != nil {
          Text(AppText.format("%@ updated · %@ failed", String(state.updated), String(state.failed)))
        } else if compact, recentCheck == nil, library.refreshMessage == nil {
          Text(AppText.text("No update checks yet"))
        }
        if let date = recentCheck, !library.updateChecksRunning {
          HStack(spacing: 4) { Text(AppText.text("Last checked")); Text(date, style: .relative) }
        }
        if let message = library.refreshMessage, !library.updateChecksRunning,
           !compact || state.failed > 0 || (state.finishedAt == nil && !state.skippedFresh) {
          Text(message).lineLimit(3)
        }
        if compact, !library.updateFailures.isEmpty {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(library.updateFailures) { failure in
                VStack(alignment: .leading, spacing: 4) {
                  Text(failure.title).forumFont(.subheadline).foregroundStyle(.primary)
                  Text(failure.message).appFont(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }.frame(maxHeight: 160)
        }
        if compact { Divider() }
        Toggle(AppText.text("Updates only"), isOn: $library.onlyUpdates).toggleStyle(.switch).disabled(library.updateChecksRunning)
      }.appFont(.caption).foregroundStyle(.secondary).textCase(nil)
    }
  }
}

struct LibraryUpdateButton: View {
  @ObservedObject var library: LibraryStore
  let refresh: () -> Void
  @State private var showingStatus = false
  private var state: LibraryCheckProgress { library.checkProgress }
  private var hasFailures: Bool { state.failed > 0 || !library.updateFailures.isEmpty }
  private var symbol: String {
    hasFailures ? "exclamationmark.triangle" : library.onlyUpdates ? "line.3.horizontal.decrease" : "arrow.clockwise"
  }
  var body: some View {
    Button { showingStatus.toggle() } label: {
      Group {
        if library.updateChecksRunning { ProgressView().controlSize(.small) }
        else { Image(forumSymbol: symbol, size: 19).foregroundStyle(hasFailures ? Color.orange : .blue) }
      }.frame(width: 44, height: 44)
    }.buttonStyle(.glass).buttonBorderShape(.circle)
      .accessibilityLabel(AppText.text("Update status and filters"))
      .accessibilityValue(library.updateChecksRunning ? AppText.text("Checking for updates") : library.onlyUpdates ? AppText.text("Updates only") : "")
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
            .disabled(library.updateChecksRunning || !library.document.hasRefreshTargets)
            .accessibilityLabel(AppText.text("Refresh"))
        }.padding(16).frame(width: 288)
          .presentationCompactAdaptation(.popover)
          .presentationBackground(.regularMaterial)
      }
      .onDisappear { showingStatus = false }
  }
}
