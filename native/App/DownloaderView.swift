import ForumUI
import SwiftUI

struct DownloaderView: View {
  @State private var address = ""
  @State private var destination: DownloadLink?
  @State private var error: String?
  @State private var unsupported: URL?
  @State private var external: URL?
  @FocusState private var editing: Bool

  var body: some View {
    List {
      HStack(spacing: 10) {
        TextField(AppText.text("Paste an HTTP or HTTPS link"), text: $address)
          .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
          .submitLabel(.go).focused($editing).onSubmit(open)
          .accessibilityLabel(AppText.text("Download link"))
        Button(action: open) {
          Image(forumSymbol: "chevron.right", size: 22).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(AppText.text("Open link"))
          .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }.appFont(.body)
      .navigationTitle(AppText.text("Downloader")).navigationBarTitleDisplayMode(.inline)
      .toolbarRole(.editor).toolbar(.visible, for: .navigationBar).toolbar(.hidden, for: .bottomBar)
      .navigationDestination(item: $destination) { target in
        switch target {
        case .gofile(let url): GofileBrowserView(url: url)
        case .hosted(let url): HostedFilesView(url: url)
        case .unsupported: EmptyView()
        }
      }
      .background { ExternalBrowserPresenter(url: $external, useFileBrowser: false) }
      .forumAlert(AppText.text("Downloader"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }), actions: {
        var actions = [ForumDialogAction(AppText.text("OK"), role: .cancel) { error = nil }]
        if let unsupported {
          actions.append(ForumDialogAction(AppText.text("Open in browser")) { external = unsupported; error = nil })
        }
        return actions
      }, message: { error ?? "" })
  }

  private func open() {
    editing = false
    unsupported = nil
    guard let target = DownloadLink.parse(address) else {
      error = AppText.text("Enter a complete HTTP or HTTPS link.")
      return
    }
    if case .unsupported(let url) = target {
      unsupported = url
      error = AppText.text("This link is not supported by the downloader. Use a Gofile, Bunkr, Pixeldrain, Fileditch, or Filester file or folder link.")
    } else {
      error = nil
      destination = target
    }
  }
}
