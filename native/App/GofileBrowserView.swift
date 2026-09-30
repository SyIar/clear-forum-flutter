import SwiftUI
import WebKit
import QuickLook
import AVKit

struct GofileDestination: Hashable { let url: URL }

struct GofileBrowserView: View {
  @StateObject private var session: GofileSession
  @State private var batch: GofileBatchDownload?
  @State private var search = ""
  @State private var showingBatch = false
  init(url: URL) {
    _session = StateObject(wrappedValue: GofileSession(url: url))
  }
  private var entries: [GofileEntry] {
    (session.listing?.entries ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
  }
  var body: some View {
    List {
      if let failure = session.failure {
        Section {
          GofileAccessView(failure: failure, busy: session.loading, retry: { session.load() },
            unlock: { _ = try? await session.unlock($0) }, website: { session.showWebsite() })
        }
      } else if let error = session.error {
        Section {
          Label(error, systemImage: "exclamationmark.triangle").appFont(.subheadline).foregroundStyle(.secondary)
          Button(AppText.text("Open website"), systemImage: "globe") { session.showWebsite() }
        }
      }
      if session.loading { HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear) }
      if let listing = session.listing, session.failure == nil, session.error == nil {
        Section {
          ForEach(entries) { entry in
            HStack(spacing: 12) {
              if entry.folder {
                NavigationLink { GofileBrowserView(url: entry.pageURL) } label: { entryLabel(entry) }
              } else if TorrentMetadata.isTorrent(name: entry.name, mime: entry.mime) {
                entryLabel(entry)
                TorrentCopyButton(load: {
                  try await session.transfer(entry, limit: Int64(TorrentMetadata.limit), progress: { _ in })
                }, unavailable: entry.unavailable)
              } else {
                Button { session.open(entry) } label: { entryLabel(entry) }.buttonStyle(.plain)
                downloadButton(entry)
              }
            }.padding(.vertical, 3)
          }
          if entries.isEmpty { Text(search.isEmpty ? AppText.text("This folder is empty.") : AppText.text("No matching files on this page.")).foregroundStyle(.secondary) }
        } header: { Text(AppText.format("%@ items · Page %@ of %@", String(describing: listing.entries.count), String(describing: listing.page), String(describing: listing.pages))) }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(session.listing?.title ?? "Gofile").navigationBarTitleDisplayMode(.inline)
    .toolbarRole(.editor)
    .searchable(text: $search, prompt: AppText.text("Find files on this page"))
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button(AppText.text("Download all"), systemImage: "arrow.down.document") {
          session.suspendThumbnails()
          if let listing = session.listing {
            batch = GofileDownloadManager.shared.batch(url: session.requestedURL, listing: listing)
          }
          showingBatch = true
        }.disabled(session.loading || session.failure != nil || session.listing == nil || session.hasDownloads)
        Button(AppText.text("Open website"), systemImage: "globe") { session.showWebsite() }
        Button(AppText.text("Refresh"), systemImage: "arrow.clockwise") { session.load() }.disabled(session.loading)
      }
      if let listing = session.listing, listing.pages > 1 {
        ToolbarItemGroup(placement: .bottomBar) {
          Button(AppText.text("Previous"), systemImage: "chevron.left") { session.load(page: listing.page - 1) }.disabled(listing.page <= 1 || session.loading)
          Text("\(listing.page) / \(listing.pages)").monospacedDigit()
          Button(AppText.text("Next"), systemImage: "chevron.right") { session.load(page: listing.page + 1) }.disabled(listing.page >= listing.pages || session.loading)
        }
      }
    }
    .task { if session.listing == nil && !session.loading { session.load() } }
    .background {
      if !session.showingWebsite { GofileWebSurface(webView: session.webView).frame(width: 1, height: 1).opacity(0).allowsHitTesting(false).accessibilityHidden(true) }
    }
    .sheet(isPresented: $session.showingWebsite, onDismiss: { session.returnToFiles() }) {
      NavigationStack {
        GofileWebSurface(webView: session.webView).ignoresSafeArea(.container, edges: .bottom)
          .navigationTitle("gofile.io").navigationBarTitleDisplayMode(.inline)
          .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(AppText.text("Files")) { session.showingWebsite = false } } }
      }
    }
    .sheet(item: $session.export) { GofileExport(file: $0.url) }
    .navigationDestination(isPresented: $showingBatch) {
      if let batch { GofileBatchView(batch: batch) }
    }
    .onChange(of: showingBatch) { _, visible in
      if !visible { session.resumeThumbnails() }
    }
    .navigationDestination(item: $session.preview) { file in
      GofileQuickLook(file: file.url).navigationTitle(AppText.text("Preview")).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .bottomBar)
    }
    .navigationDestination(item: $session.video) { source in
      GofileVideoView(source: source).navigationTitle(AppText.text("Video")).navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .bottomBar)
    }
  }
  private func entryLabel(_ entry: GofileEntry) -> some View {
    HStack(spacing: 12) {
      GofileThumbnail(entry: entry, session: session)
      VStack(alignment: .leading, spacing: 4) {
        Text(entry.name).appFont(.subheadline).lineLimit(2).foregroundStyle(.primary)
        Text(entry.folder ? AppText.text("Folder") : entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? AppText.text("Size unknown"))
          .appFont(.caption).foregroundStyle(.secondary)
        if entry.unavailable { Text(AppText.text("Unavailable on Gofile")).appFont(.caption2).foregroundStyle(.secondary) }
        if let error = session.downloads[entry.id]?.error { Text(error).appFont(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.contentShape(Rectangle())
  }
  private func downloadButton(_ entry: GofileEntry) -> some View {
    let state = session.downloads[entry.id]
    return Button {
      if state?.busy == true { session.cancel(entry.id) } else { session.download(entry) }
    } label: {
      ZStack {
        if state?.busy == true {
          if let fraction = state?.progress {
            Circle().stroke(.blue.opacity(0.15), lineWidth: 2.5)
            Circle().trim(from: 0, to: fraction).stroke(.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int(fraction * 100))").font(.system(size: 10, weight: .semibold)).monospacedDigit()
          } else { ProgressView() }
        } else { Image(systemName: state?.file == nil ? "arrow.down" : "square.and.arrow.up").font(.body.weight(.medium)) }
      }.frame(width: 28, height: 28).padding(6)
    }.buttonStyle(.glass).buttonBorderShape(.circle)
      .accessibilityLabel(state?.busy == true ? AppText.text("Cancel download") : state?.file == nil ? AppText.text("Download file") : AppText.text("Save to Files"))
      .disabled(entry.unavailable)
  }
}

private struct GofileThumbnail: View {
  let entry: GofileEntry
  @ObservedObject var session: GofileSession
  @State private var image: UIImage?
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemFill))
      if let image { Image(uiImage: image).resizable().scaledToFill() }
      else { Image(systemName: entry.symbol).font(.title2).foregroundStyle(.blue) }
    }.frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10))
      .task(id: "\(session.revision):\(entry.thumbnail?.absoluteString ?? entry.id)") { image = await session.thumbnail(entry) }
      .accessibilityHidden(true)
  }
}

struct GofileWebSurface: UIViewRepresentable {
  let webView: WKWebView
  func makeUIView(context: Context) -> WKWebView { webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
struct GofileExport: UIViewControllerRepresentable {
  let file: URL
  func makeUIViewController(context: Context) -> UIDocumentPickerViewController { UIDocumentPickerViewController(forExporting: [file], asCopy: true) }
  func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
struct GofileQuickLook: UIViewControllerRepresentable {
  let file: URL
  func makeCoordinator() -> Coordinator { Coordinator(file: file) }
  func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = EdgeAwareQuickLookController(); controller.dataSource = context.coordinator; return controller
  }
  func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
  final class Coordinator: NSObject, QLPreviewControllerDataSource {
    let file: URL
    init(file: URL) { self.file = file }
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { file as NSURL }
  }
}
private struct GofileVideoView: UIViewControllerRepresentable {
  let source: GofileVideoSource
  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    let asset = AVURLAsset(url: source.url, options: [AVURLAssetHTTPCookiesKey: source.cookies])
    controller.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    controller.player?.play()
    return controller
  }
  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
  static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: ()) { controller.player?.pause(); controller.player = nil }
}

// Used by external links from the forum's website view; reader links use a normal push.
struct GofileModalRoot: View {
  let url: URL
  var close: () -> Void
  var body: some View {
    NavigationStack {
      GofileBrowserView(url: url).toolbar {
        ToolbarItem(placement: .topBarLeading) { Button(AppText.text("Back"), systemImage: "chevron.left", action: close) }
      }
    }.appFont(.body)
      .environment(\.locale, AppText.locale)
  }
}

// Quick Look's image scroll view must yield a left-edge gesture to the enclosing
// NavigationStack, even while the image is zoomed. Keep system delegates intact.
private final class EdgeAwareQuickLookController: QLPreviewController {
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    configureEdgeReturn(in: view)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    configureEdgeReturn(in: view)
  }
  private func configureEdgeReturn(in root: UIView) {
    guard let edge = navigationController?.interactivePopGestureRecognizer else { return }
    func visit(_ view: UIView) {
      if let scroll = view as? UIScrollView { scroll.panGestureRecognizer.require(toFail: edge) }
      for child in view.subviews { visit(child) }
    }
    visit(root)
  }
}
