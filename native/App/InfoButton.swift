import ForumUI
import SwiftUI

struct InfoButton: View {
  let title: String
  let message: String
  @State private var showingInfo = false

  var body: some View {
    Button { showingInfo = true } label: {
      Image(systemName: "info.circle")
    }.buttonStyle(.borderless)
      .accessibilityLabel(AppText.format("%@ information", String(describing: title)))
      .forumAlert(title, isPresented: $showingInfo, actions: {
        [ForumDialogAction(AppText.text("OK"))]
      }, message: { message })
  }
}
