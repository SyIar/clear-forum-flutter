import ForumUI
import SwiftUI

enum ReaderBottomPanel: Equatable {
  case pages, actions
}

// Both panels use one horizontal glass capsule and equal action columns.
private struct ReaderControlGroup<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View {
    HStack(spacing: 0, content: content)
      .frame(width: 240, height: 48)
      .padding(4)
      .glassEffect(.regular.interactive(), in: .capsule)
  }
}

private struct ReaderControlButton<Content: View>: View {
  let title: String
  let disabled: Bool
  let perform: () -> Void
  @ViewBuilder let content: () -> Content
  var body: some View {
    Button(action: perform) {
      content()
        .frame(maxWidth: .infinity, minHeight: 48)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain).foregroundStyle(.blue).disabled(disabled)
    .opacity(disabled ? 0.4 : 1).accessibilityLabel(title)
  }
}

struct ReaderPagingActions: View {
  let pageNumber: Int
  let canGoBack: Bool
  let canGoForward: Bool
  let canSelect: Bool
  let previous: () -> Void
  let select: () -> Void
  let next: () -> Void
  var body: some View {
    ReaderControlGroup {
      ReaderControlButton(title: AppText.text("Previous page"), disabled: !canGoBack, perform: previous) {
        Image(forumSymbol: "chevron.left", size: 22)
      }
      Divider().frame(height: 20)
      ReaderControlButton(title: AppText.text("Choose page"), disabled: !canSelect, perform: select) {
        Text(AppText.format("Page %@", String(pageNumber)))
          .appFont(.subheadline, weight: .semibold).monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 2)
      }.accessibilityValue(AppText.format("Page %@", String(pageNumber)))
      Divider().frame(height: 20)
      ReaderControlButton(title: AppText.text("Next page"), disabled: !canGoForward, perform: next) {
        Image(forumSymbol: "chevron.right", size: 22)
      }
    }
  }
}

struct ReaderQuickActions: View {
  let canJump: Bool
  let busy: Bool
  let top: () -> Void
  let bottom: () -> Void
  let refresh: () -> Void
  var settings: (() -> Void)? = nil
  var body: some View {
      ReaderControlGroup {
        action(AppText.text("Top of page"), symbol: "arrow.up.to.line", disabled: !canJump || busy, perform: top)
        Divider().frame(height: 20)
        action(AppText.text("Bottom of page"), symbol: "arrow.down.to.line", disabled: !canJump || busy, perform: bottom)
        Divider().frame(height: 20)
        action(AppText.text(settings == nil ? "Refresh" : "Reading settings"), symbol: settings == nil ? "arrow.clockwise" : "gearshape", disabled: busy, perform: settings ?? refresh)
      }
  }
  private func action(_ title: String, symbol: String, disabled: Bool, perform: @escaping () -> Void) -> some View {
    ReaderControlButton(title: title, disabled: disabled, perform: perform) {
      Image(forumSymbol: symbol, size: 22)
    }
  }
}

struct ReturnToReadingButton: View {
  let restore: () -> Void
  let dismiss: () -> Void
  var body: some View {
    HStack(spacing: 0) {
      Button(action: restore) { Image(forumSymbol: "arrow.uturn.backward", size: 21).frame(width: 52, height: 44) }
        .accessibilityLabel(AppText.text("Return to reading position"))
      Divider().frame(height: 18)
      Button(action: dismiss) { Image(forumSymbol: "xmark", size: 14).frame(width: 44, height: 44) }
        .accessibilityLabel(AppText.text("Keep this reading position"))
    }.buttonStyle(.plain).foregroundStyle(.blue).padding(4).glassEffect(.regular.interactive(), in: .capsule)
      .padding(.bottom, 12)
  }
}
