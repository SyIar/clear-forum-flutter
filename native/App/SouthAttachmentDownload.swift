import SwiftUI
import WebKit
import ForumUI

@MainActor enum SouthAttachmentAccess {
  // Uses the same persistent South WebKit profile, including after a relaunch.
  static let session = ForumSession(site: .south)
  static func cookies(for url: URL) async -> [HTTPCookie] {
    await session.store.httpCookieStore.allCookies().filter { SouthSitePolicy.matches($0, url: url) }
  }
}

struct SouthAttachmentDownload: View {
  let url: URL
  let name: String
  @ObservedObject private var downloads = HostedDownloadManager.shared
  @State private var preview: GofileLocalFile?
  @State private var export: GofileLocalFile?
  private var entry: HostedFileEntry {
    HostedFileEntry(pageURL: url, name: name, mime: HostedFilePolicy.mime(name))
  }
  var body: some View {
    let task = downloads.download(for: entry)
    let file = task?.file(for: entry).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    HStack(spacing: 10) {
      Button {
        if let file { preview = GofileLocalFile(url: file) } else { open(task) }
      } label: {
        Label(name, forumSymbol: "doc").forumFont(.subheadline)
          .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
      }.buttonStyle(.plain)
      FileDownloadAction(exists: task != nil, running: task?.running == true,
                         completed: file != nil, progress: task?.progress) {
        if let file { export = GofileLocalFile(url: file) } else { open(task) }
      }
    }.padding(10).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
      .navigationDestination(item: $preview) { LocalFilePreview(file: $0.url) }
      .sheet(item: $export) { GofileExport(file: $0.url) }
  }
  private func open(_ task: HostedBatchDownload?) {
    if task != nil { VideoDownloadManager.shared.showingManager = true }
    else { downloads.enqueue(HostedFileListing(url: url, title: name, entries: [entry])) }
  }
}
