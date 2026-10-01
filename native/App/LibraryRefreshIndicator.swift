import ForumUI
import SwiftUI

struct LibraryRefreshIndicator: View {
  let phase: ForumRefreshPhase?
  var showsChevron = false
  private var status: String {
    switch phase {
    case .checking: return AppText.text("Checking for updates")
    case .checked: return AppText.text("Update check completed")
    case .updated: return AppText.text("New updates found")
    case .failed: return AppText.text("Update check failed")
    case nil: return ""
    }
  }
  var body: some View {
    Group {
      switch phase {
      case .checking: ProgressView().controlSize(.mini).tint(.blue)
      case .checked: Image(forumSymbol: "checkmark", size: 14).foregroundStyle(.secondary)
      case .updated: Image(forumSymbol: "checkmark.circle", size: 16).foregroundStyle(.blue)
      case .failed: Image(forumSymbol: "exclamationmark.triangle", size: 16).foregroundStyle(.orange)
      case nil:
        if showsChevron { Image(forumSymbol: "chevron.right", size: 12).foregroundStyle(.tertiary) }
        else { Color.clear }
      }
    }
    .frame(width: 18, height: 18)
    .accessibilityElement(children: .ignore).accessibilityLabel(status)
    .accessibilityHidden(phase == nil)
    .allowsHitTesting(false)
  }
}
