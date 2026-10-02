import SwiftUI
import ForumUI

struct FileListingHeader: View {
  let title: String
  let count: Int
  let canDownload: Bool
  var disabled = false
  var album = false
  let download: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: ForumDesignSystem.spacing.base) {
      Text(title).appFont(.headline).textSelection(.enabled)
      if album { Label(AppText.text("Showing the complete album"), forumSymbol: "rectangle.stack").appFont(.caption).foregroundStyle(.secondary) }
      HStack(spacing: 12) {
        if canDownload { Button(AppText.text("Download all"), action: download).buttonStyle(ForumActionButtonStyle()).disabled(disabled) }
        Spacer(minLength: 0)
        Text(count == 1 ? AppText.text("1 item") : AppText.format("%@ items", String(count)))
          .appFont(.caption).foregroundStyle(.secondary).lineLimit(1).fixedSize()
      }
    }.padding(ForumDesignSystem.spacing.cardPadding).forumCardSurface()
      .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
  }
}

struct FileDownloadAction: View {
  let exists: Bool
  let running: Bool
  let completed: Bool
  let progress: Double?
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      ZStack {
        if running {
          if let progress {
            Circle().stroke(.blue.opacity(0.15), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0, min(1, progress)))
              .stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
          } else { ProgressView().controlSize(.small) }
        } else { Image(forumSymbol: completed ? "square.and.arrow.up" : exists ? "clock" : "arrow.down.circle", size: 20) }
      }.frame(width: 28, height: 28).frame(width: 44, height: 44).contentShape(Rectangle())
    }.buttonStyle(.borderless)
      .accessibilityLabel(completed ? AppText.text("Save to Files") : exists ? AppText.text("Downloads") : AppText.text("Download file"))
      .accessibilityValue(running ? progress.map { "\(Int($0 * 100))%" } ?? AppText.text("Preparing") : "")
  }
}
