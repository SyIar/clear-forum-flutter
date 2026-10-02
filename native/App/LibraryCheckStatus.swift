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
}

struct LibraryCheckStatus: View {
  @ObservedObject var library: LibraryStore
  private var recentCheck: Date? {
    (library.document.threads.values.compactMap(\.checkedAt) + library.document.following.compactMap(\.checkedAt) + library.document.readingBooks.compactMap(\.checkedAt)).max()
  }
  var body: some View {
    let state = library.checkProgress
    if state.running || recentCheck != nil || library.refreshMessage != nil || state.skippedFresh {
      VStack(alignment: .leading, spacing: 4) {
        if state.running {
          HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(AppText.format("Checking %@/%@", String(min(state.total, state.completed + 1)), String(state.total)))
          }
        } else if state.skippedFresh {
          Text(AppText.text("Checked within the last hour. No items need refreshing."))
        } else if state.finishedAt != nil {
          Text(AppText.format("%@ updated · %@ failed", String(state.updated), String(state.failed)))
        }
        if let date = recentCheck, !state.running {
          HStack(spacing: 4) { Text(AppText.text("Last checked")); Text(date, style: .relative) }
        }
        if let message = library.refreshMessage, !state.running { Text(message).lineLimit(3) }
      }.appFont(.caption).foregroundStyle(.secondary).textCase(nil)
    }
  }
}
