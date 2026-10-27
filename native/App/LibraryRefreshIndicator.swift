import SwiftUI

enum ForumRefreshPhase: Equatable {
  case checking, checked, updated, failed
}

struct LibraryRefreshIndicator: View {
  let phase: ForumRefreshPhase?
  var showsChevron = false
  @ScaledMetric(relativeTo: .caption) private var size = 18.0
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
      if showsChevron, phase != .checking {
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      } else {
        switch phase {
      case .checking: ProgressView().controlSize(.mini).tint(.blue)
      case .checked: Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
      case .updated: Image(systemName: "checkmark.circle").font(.caption).foregroundStyle(.blue)
      case .failed: Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
      case nil:
        if showsChevron { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
        else { Color.clear }
        }
      }
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore).accessibilityLabel(status)
    .accessibilityHidden(phase == nil || (showsChevron && phase != .checking))
    .allowsHitTesting(false)
  }
}
