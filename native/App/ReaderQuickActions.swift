import SwiftUI

enum ReaderBottomPanel: Equatable {
  case pages, actions
}

// One native material surface contains the reader controls, like a floating toolbar.
private struct ReaderControlGroup<Content: View>: View {
  @ViewBuilder let content: () -> Content
  var body: some View {
    HStack(spacing: 0, content: content)
      .frame(maxWidth: 320)
      .padding(8)
      .glassEffect(.regular, in: .capsule)
      .padding(.horizontal, 16)
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
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless).disabled(disabled).accessibilityLabel(title)
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
        Image(systemName: "chevron.left")
      }
      Divider().frame(height: 20)
      ReaderControlButton(title: AppText.text("Choose page"), disabled: !canSelect, perform: select) {
        Text(AppText.format("Page %@", String(pageNumber)))
          .appFont(.subheadline, weight: .semibold).monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 2)
      }.accessibilityValue(AppText.format("Page %@", String(pageNumber)))
      Divider().frame(height: 20)
      ReaderControlButton(title: AppText.text("Next page"), disabled: !canGoForward, perform: next) {
        Image(systemName: "chevron.right")
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
      Image(systemName: symbol)
    }
  }
}

struct ReturnToReadingButton: View {
  var restoreDisabled = false
  let restore: () -> Void
  let dismiss: () -> Void
  var body: some View {
    HStack(spacing: 0) {
      Button(action: restore) {
        Image(systemName: "arrow.uturn.backward").font(.system(size: 21)).frame(width: 52, height: 44).contentShape(Rectangle())
      }.disabled(restoreDisabled)
        .accessibilityLabel(AppText.text("Return to reading position"))
      Divider().frame(height: 18)
      Button(action: dismiss) {
        Image(systemName: "xmark").font(.system(size: 14)).frame(width: 44, height: 44).contentShape(Rectangle())
      }
        .accessibilityLabel(AppText.text("Keep this reading position"))
    }.buttonStyle(.borderless).padding(4).glassEffect(.regular, in: .capsule)
      .padding(.bottom, 12)
  }
}
