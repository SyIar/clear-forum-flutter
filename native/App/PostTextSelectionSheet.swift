import SwiftUI
import UIKit

struct PostTextSelection: Identifiable {
  let id = UUID()
  let text: String
}

struct PostTextSelectionSheet: View {
  let selection: PostTextSelection
  @Environment(\.dismiss) private var dismiss
  @State private var copied = false
  var body: some View {
    NavigationStack {
      Group {
        if selection.text.isEmpty {
          ContentUnavailableView(AppText.text("No text to copy"), systemImage: "text.alignleft")
        } else {
          SelectablePostText(text: selection.text).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .safeAreaInset(edge: .bottom) {
        Button {
          UIPasteboard.general.string = selection.text
          copied = true
        } label: {
          Label(AppText.text("Copy all"), systemImage: copied ? "checkmark" : "doc.on.doc")
            .forumFont(.headline).padding(.horizontal, 16).padding(.vertical, 8)
        }.buttonStyle(.glass).disabled(selection.text.isEmpty)
          .accessibilityValue(copied ? AppText.text("Copied") : "")
          .padding(.bottom, 12)
      }
      .navigationTitle(AppText.text("Text selection")).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(AppText.text("Done"), systemImage: "xmark") { dismiss() }
        }
      }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}

private struct SelectablePostText: UIViewRepresentable {
  let text: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.isEditable = false
    view.isSelectable = true
    view.backgroundColor = .clear
    view.alwaysBounceVertical = true
    view.textContainerInset = UIEdgeInsets(top: 18, left: 20, bottom: 24, right: 20)
    view.textContainer.lineFragmentPadding = 0
    view.adjustsFontForContentSizeCategory = true
    view.dataDetectorTypes = []
    return view
  }
  func updateUIView(_ view: UITextView, context: Context) {
    // Avoid resetting the user's selection while the sheet updates.
    if view.text != text { view.text = text }
    let font = AppTypography.uiFont(.body)
    if view.font != font { view.font = font }
    view.textColor = .label
  }
}
