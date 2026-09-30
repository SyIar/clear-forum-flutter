import SwiftUI

struct ReaderDiagnosticsView: View {
  let url: URL
  let context: String
  @ObservedObject var session: ForumSession
  @Environment(\.dismiss) private var dismiss
  @State private var snapshot: ReaderDiagnosticSnapshot?
  @State private var copied = false
  @State private var capturing = false
  private var report: String {
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return "Forum Lite build \(build)\niOS \(UIDevice.current.systemVersion)\n" +
      (snapshot?.report ?? ReaderDiagnostics.address(url.absoluteString)) + "\n" + context +
      "\n\nImage requests (latest 40):\n" + session.images.diagnosticReport
  }
  var body: some View {
    NavigationStack {
      List {
        Section {
          Button(AppText.text("Copy loading diagnostics"), systemImage: "doc.on.doc") { copy(report) }
          Button(AppText.text("Copy page HTML"), systemImage: "chevron.left.forwardslash.chevron.right") {
            copy(report + "\n\n" + ReaderDiagnostics.htmlExport(snapshot?.html ?? ""))
          }.disabled(snapshot?.html.isEmpty ?? true)
          if snapshot == nil {
            Button(AppText.text("Capture page diagnostics"), systemImage: "arrow.clockwise") {
              capturing = true
              Task {
                _ = try? await session.load(url)
                snapshot = session.diagnostic(for: url)
                capturing = false
              }
            }.disabled(capturing)
            if capturing { ProgressView() }
          }
          if copied { Label(AppText.text("Copied"), systemImage: "checkmark").foregroundStyle(.secondary) }
        } footer: {
          Text(AppText.text("Exports include page content and image addresses. Cookies, form values and scripts are removed. Nothing is uploaded automatically."))
        }
        Section(AppText.text("Loading diagnostics")) {
          Text(report).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
      }.navigationTitle(AppText.text("Page diagnostics")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(AppText.text("Done")) { dismiss() } } }
        .onAppear { snapshot = session.diagnostic(for: url) }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
  private func copy(_ text: String) {
    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true])
    copied = true
  }
}
