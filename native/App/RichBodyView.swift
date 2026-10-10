import ForumUI
import SwiftUI
import ImageIO

private struct ReaderRefererKey: EnvironmentKey { static let defaultValue: URL? = nil }
extension EnvironmentValues {
  var readerReferer: URL? {
    get { self[ReaderRefererKey.self] }
    set { self[ReaderRefererKey.self] = newValue }
  }
}

struct ForumTagStrip: View {
  let tags: [ForumTag]
  let navigate: (URL) -> Void
  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 5) {
        ForEach(tags) { tag in
          Button { navigate(tag.url) } label: {
            Text(tag.title).forumFont(.caption2, weight: .semibold).lineLimit(1)
              .forumTagSurface()
          }.buttonStyle(.plain).accessibilityLabel(AppText.format("Filter by %@", String(describing: tag.title)))
        }
      }.padding(.vertical, 2)
    }.scrollIndicators(.hidden)
  }
}

struct ForumEntryCard: View {
  let entry: ForumEntry
  let isForum: Bool
  let navigate: (URL) -> Void
  var formatBookhouseTitle = false
  private var bookTitle: BookhouseTitlePresentation? {
    guard formatBookhouseTitle, BookhouseSitePolicy.threadKey(entry.url) != nil else { return nil }
    return BookhouseTitlePresentation(title: entry.title, postingAuthor: entry.authorName ?? entry.subtitle)
  }
  private var inlineMetadata: Bool { SouthSitePolicy.isThread(entry.url) || bookTitle != nil }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !entry.tags.isEmpty { ForumTagStrip(tags: entry.tags, navigate: navigate) }
      Button { navigate(entry.url) } label: {
        HStack(spacing: 10) {
          if bookTitle != nil { Image(forumSymbol: "book").foregroundStyle(.blue) }
          else if let thumbnail = entry.thumbnail { ForumThumbnail(url: thumbnail, compact: entry.pinned) }
          else { Image(forumSymbol: entry.pinned ? "pin.fill" : (isForum ? "folder" : "text.bubble")).foregroundStyle(.blue) }
          VStack(alignment: .leading, spacing: 4) {
            if let tags = bookTitle?.tags, !tags.isEmpty {
              ScrollView(.horizontal) {
                HStack(spacing: 5) {
                  ForEach(tags, id: \.self) { tag in
                    Text(tag).forumFont(.caption2, weight: .semibold).forumTagSurface()
                  }
                }
              }.scrollIndicators(.hidden)
            }
            Text(bookTitle?.title ?? entry.title).forumFont(entry.pinned ? .subheadline : .body).lineLimit(entry.pinned ? 1 : 3).foregroundStyle(.primary)
            if !entry.excerpt.isEmpty { Text(entry.excerpt).forumFont(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            if inlineMetadata, !entry.pinned {
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(bookTitle?.author ?? entry.authorName ?? entry.subtitle).forumFont(.caption2).lineLimit(1)
                Spacer(minLength: 6)
                if let date = entry.postedAt { Text(date).fixedSize(horizontal: true, vertical: false) }
                if let count = entry.totalPostCount { Text(AppText.format("%@ posts", String(count))).monospacedDigit().fixedSize() }
              }.appFont(.caption2).foregroundStyle(.secondary)
            } else if !entry.pinned && !entry.subtitle.isEmpty {
              Text(entry.subtitle).forumFont(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if !inlineMetadata, entry.postedAt != nil || entry.totalPostCount != nil {
              HStack(spacing: 8) {
                if let date = entry.postedAt, !entry.subtitle.contains(date) { Text(date) }
                if let count = entry.totalPostCount { Text(AppText.format("%@ posts", String(describing: count))).monospacedDigit() }
              }.appFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          Spacer(minLength: 0)
          Image(forumSymbol: "chevron.right", size: 12).font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
    }.padding(ForumDesignSystem.spacing.cardPadding).forumCardSurface()
  }
}

struct ForumThumbnail: View {
  @EnvironmentObject private var session: ForumSession
  let url: URL
  var compact = false
  @State private var image: UIImage?
  @State private var loading = true
  @State private var imageURL: URL?
  var body: some View {
    ZStack {
      Color(uiColor: .tertiarySystemFill)
      if let image { Image(uiImage: image).resizable().scaledToFill() }
      else if loading { ProgressView().controlSize(.small) }
      else { Image(forumSymbol: "photo", size: 12).font(.caption).foregroundStyle(.secondary) }
    }.frame(width: compact ? 28 : 72, height: compact ? 28 : 50)
      .clipShape(RoundedRectangle(cornerRadius: compact ? 6 : 9))
      .accessibilityHidden(true)
      .task(id: url) {
        guard image == nil || imageURL != url else { return }
        imageURL = url
        loading = true
        image = nil
        let loaded = await session.images.load(url, referer: session.site.base)
        guard !Task.isCancelled, imageURL == url else { return }
        image = loaded
        loading = false
      }
  }
}

struct PostCard: View {
  let post: ForumPost
  let posters: PosterStore
  let navigate: (URL) -> Void
  let play: (BodyBlock) -> Void
  let openImage: (ImageViewerSource) -> Void
  let purchase: (SouthPurchaseOffer) -> Void
  let purchasing: Bool
  var authorFilterActive = false
  var isOriginalPoster = false
  var openAvatar: (() -> Void)?
  var selectText: (() -> Void)?
  var body: some View {
    VStack(alignment: .leading, spacing: ForumDesignSystem.spacing.md) {
      HStack(spacing: ForumDesignSystem.spacing.md) {
        PostAvatar(url: post.avatar, author: post.author)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 4) {
            Text(post.author).forumFont(.subheadline, weight: .bold)
            if isOriginalPoster { ForumOriginalPosterBadge(label: AppText.text("Original poster")) }
          }
          if openAvatar == nil, post.authorID != nil || !post.date.isEmpty {
            HStack(spacing: 6) {
              if let id = post.authorID { Text(AppText.format("UID %@", String(describing: id))) }
              if post.authorID != nil && !post.date.isEmpty { Text("\u{00B7}") }
              if !post.date.isEmpty { Text(post.date.replacingOccurrences(of: "T", with: " ").prefix(16)) }
            }.appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        if !post.number.isEmpty { Text(post.number).appFont(.caption, weight: .semibold).foregroundStyle(.blue) }
        if let openAvatar, let selectText {
          SouthPostMenu(post: post, busy: purchasing, authorFilterActive: authorFilterActive,
                        navigate: navigate, openAvatar: openAvatar, selectText: selectText)
        }
      }
      if openAvatar != nil {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          if let id = post.authorID { Text(AppText.format("UID %@", id)).fixedSize() }
          Spacer(minLength: 4)
          if !post.date.isEmpty {
            Text(post.date.replacingOccurrences(of: "T", with: " "))
              .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
          }
        }.appFont(.caption2).foregroundStyle(.secondary)
      }
      Divider()
      RichBodyView(blocks: post.blocks, posters: posters, navigate: navigate, play: play, openImage: { source in
        var source = source
        source.gallery = imageGallery(in: post.blocks)
        openImage(source)
      }, purchase: purchase, purchasing: purchasing)
    }.padding(ForumDesignSystem.spacing.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
      .forumCardSurface()
  }
}

private func imageGallery(in blocks: [BodyBlock]) -> [ImageGalleryEntry] {
  var seen = Set<URL>()
  func collect(_ blocks: [BodyBlock]) -> [ImageGalleryEntry] {
    blocks.flatMap { block in
      if block.kind == .image, let preview = block.url, let url = block.original ?? block.url, seen.insert(url).inserted {
        return [ImageGalleryEntry(url: url, previewURL: preview)]
      }
      return collect(block.children)
    }
  }
  return collect(blocks)
}

struct PostAvatar: View {
  let url: URL?
  let author: String
  var action: ((UIImage?) -> Void)?
  @EnvironmentObject private var session: ForumSession
  @State private var image: UIImage?
  @State private var imageURL: URL?
  private var avatar: some View {
    Color.blue.opacity(0.12).frame(width: 36, height: 36)
      .overlay {
        if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: 36, height: 36) }
        else { Text(String(author.prefix(1)).uppercased()).forumFont(.headline).foregroundStyle(.blue) }
      }.clipShape(Circle())
  }
  var body: some View {
    Group {
      if let action {
        Button { action(image) } label: { avatar.frame(width: 44, height: 44).contentShape(Rectangle()) }
          .buttonStyle(.plain).accessibilityLabel(AppText.format("Actions for %@", String(describing: author)))
      } else { avatar.accessibilityHidden(true) }
    }.frame(width: 44, height: 44)
      .task(id: url) {
        guard image == nil || imageURL != url else { return }
        imageURL = url
        image = nil
        guard let url else { return }
        let loaded = await session.images.load(url, referer: session.site.base)
        guard !Task.isCancelled, imageURL == url else { return }
        image = loaded
      }
  }
}

private struct BodyGroup: Identifiable {
  var id: UUID { blocks[0].id }
  let blocks: [BodyBlock]
}
struct RichBodyView: View {
  @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17
  @ScaledMetric(relativeTo: .body) private var novelLineSpacing: CGFloat = 7
  @ScaledMetric(relativeTo: .body) private var novelParagraphSpacing: CGFloat = 14
  @Environment(\.readerBodyStyle) private var bodyStyle
  @Environment(\.readingAppearance) private var appearance
  @EnvironmentObject private var session: ForumSession
  private var bodyTextSize: CGFloat { bodyStyle == .novel ? textSize * (appearance.fontSize / 17.0) : textSize }
  let blocks: [BodyBlock]
  let posters: PosterStore
  let navigate: (URL) -> Void
  let play: (BodyBlock) -> Void
  let openImage: (ImageViewerSource) -> Void
  let purchase: (SouthPurchaseOffer) -> Void
  let purchasing: Bool
  private var groups: [BodyGroup] {
    var result: [BodyGroup] = []
    var images: [BodyBlock] = []
    for block in blocks {
      if block.kind == .image { images.append(block) }
      else {
        if !images.isEmpty { result.append(BodyGroup(blocks: images)); images = [] }
        result.append(BodyGroup(blocks: [block]))
      }
    }
    if !images.isEmpty { result.append(BodyGroup(blocks: images)) }
    return result
  }
  var body: some View {
    VStack(alignment: .leading, spacing: bodyStyle == .novel ? novelParagraphSpacing * appearance.paragraphSpacing / 14 : 10) {
      ForEach(groups) { group in
        if group.blocks[0].kind == .image {
          if group.blocks.count == 1 { image(group.blocks[0], grid: false) }
          else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
              ForEach(group.blocks) { block in image(block, grid: true) }
            }
          }
        } else { blockView(group.blocks[0]) }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
      .environment(\.openURL, OpenURLAction { url in navigate(url); return .handled })
  }
  private func image(_ block: BodyBlock, grid: Bool) -> some View {
    RemoteImageView(url: block.url, originalURL: block.original, ratio: grid ? 1 : block.aspectRatio, maximumHeight: grid ? 180 : 360, openImage: openImage)
  }
  @ViewBuilder private func blockView(_ block: BodyBlock) -> some View {
    switch block.kind {
    case .paragraph:
      VStack(alignment: .leading, spacing: 6) {
        ForEach(ExternalLinkPresentation.segments(block.runs, site: session.site)) { segment in
          if let url = segment.url { CompactLink(url: url, label: segment.label, navigate: navigate) }
          else { paragraphText(segment.runs) }
        }
      }
    case .link:
      if let url = block.url {
        if session.site == .south, SouthAttachment(url: url) != nil {
          SouthAttachmentDownload(url: url, name: block.label)
        } else { CompactLink(url: url, label: block.label, navigate: navigate) }
      }
    case .media:
      MediaRow(block: block, posters: posters, play: play)
    case .quote:
      HStack(alignment: .top, spacing: 9) {
        RoundedRectangle(cornerRadius: 2).fill(.blue.opacity(0.4)).frame(width: 3)
        VStack(alignment: .leading, spacing: 6) {
          if !block.label.isEmpty { Text(block.label).forumFont(.caption, weight: .bold).foregroundStyle(.secondary) }
          AnyView(RichBodyView(blocks: block.children, posters: posters, navigate: navigate, play: play, openImage: openImage, purchase: purchase, purchasing: purchasing))
        }
      }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    case .spoiler:
      DisclosureGroup {
        AnyView(RichBodyView(blocks: block.children, posters: posters, navigate: navigate, play: play, openImage: openImage, purchase: purchase, purchasing: purchasing)).padding(.top, 8)
      } label: { Text(block.label).forumFont(.subheadline) }
    case .code:
      ScrollView(.horizontal) { Text(block.label).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(10) }
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    case .image: EmptyView()
    case .purchase:
      if let offer = block.purchase {
        HStack(spacing: 12) {
          Image(forumSymbol: "lock.fill").foregroundStyle(.secondary)
          Text(AppText.format("%@ SP", String(describing: offer.priceText))).appFont(.subheadline, weight: .semibold)
          Spacer(minLength: 0)
          Button { purchase(offer) } label: {
            if purchasing { ProgressView().controlSize(.small) }
            else { Text(offer.isFree ? AppText.text("Unlock free") : AppText.text("Buy")) }
          }.appFont(.body).buttonStyle(.glass).disabled(purchasing)
        }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
      }
    }
  }
  @ViewBuilder private func paragraphText(_ runs: [TextRun]) -> some View {
    if runs.contains(where: { $0.emoticon != nil }) { EmoticonText(runs: runs) }
    else if let url = standaloneLink(runs) { CompactLink(url: url, label: runs.map(\.text).joined(), navigate: navigate) }
    else {
      Text(attributed(runs)).font(Font(MixedScriptFont.font(size: bodyTextSize, bold: false)))
        .lineSpacing(bodyStyle == .novel ? novelLineSpacing * appearance.lineSpacing / 7 : 2)
        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func standaloneLink(_ runs: [TextRun]) -> URL? {
    let visible = runs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard let url = visible.first?.url, visible.allSatisfy({ $0.url == url }) else { return nil }
    return url
  }
  private func attributed(_ runs: [TextRun]) -> AttributedString {
    var result = AttributedString()
    for run in runs {
      result.append(AppTypography.richText(run, size: bodyTextSize))
    }
    return result
  }
}
struct CompactLink: View {
  @EnvironmentObject private var session: ForumSession
  let url: URL
  let label: String
  let navigate: (URL) -> Void
  var body: some View {
    Button { navigate(url) } label: {
      HStack(spacing: 5) {
        Image(forumSymbol: "link", size: 11).font(.system(size: 11))
        Text(ExternalLinkPresentation.title(url: url, label: label, site: session.site))
          .forumFont(.caption).lineLimit(1).truncationMode(.middle)
        Image(forumSymbol: "arrow.up.right", size: 9).font(.system(size: 9))
      }.padding(.horizontal, ForumDesignSystem.spacing.sm).padding(.vertical, 6)
        .background(ForumDesignSystem.surface, in: RoundedRectangle(cornerRadius: ForumDesignSystem.radius.md, style: .continuous))
    }.buttonStyle(.plain).foregroundStyle(ForumDesignSystem.primary)
      .accessibilityLabel(label.isEmpty ? url.absoluteString : label)
  }
}
struct MediaRow: View {
  let block: BodyBlock
  let posters: PosterStore
  let play: (BodyBlock) -> Void
  @EnvironmentObject private var session: ForumSession
  @Environment(\.readerReferer) private var referer
  @State private var poster: UIImage?
  @State private var fetching = true
  @State private var posterSource: URL?
  var body: some View {
    Button { play(block) } label: {
      ZStack {
        Color(uiColor: .tertiarySystemFill)
        if let poster {
          Image(uiImage: poster).resizable().scaledToFill()
            .frame(width: 150, height: 84).clipped()
        }
        Image(forumSymbol: "play.fill", size: 18).font(.system(size: 18, weight: .semibold))
          .offset(x: 1).frame(width: 40, height: 40).foregroundStyle(.white)
          .background(.black.opacity(0.48), in: Circle())
          .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
      }.frame(width: 150, height: 84)
        .overlay(alignment: .topTrailing) {
          if fetching {
            ProgressView().controlSize(.mini).tint(.white).padding(4)
              .background(.black.opacity(0.48), in: Circle()).padding(6)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }.buttonStyle(.plain).disabled(block.url == nil)
      .accessibilityElement(children: .ignore).accessibilityLabel(AppText.text("Play"))
      .task(id: block.url) {
      guard poster == nil || posterSource != block.url else { return }
      posterSource = block.url
      poster = nil
      fetching = true
      let resolved = await posters.resolve(block, session: session)
      guard !Task.isCancelled, posterSource == block.url else { return }
      let loaded = if let resolved { await session.images.load(resolved, referer: referer ?? session.site.base) } else { nil as UIImage? }
      guard !Task.isCancelled, posterSource == block.url else { return }
      poster = loaded
      fetching = false
    }
  }
}

@MainActor
final class ImageStore {
  let offlineThreadID: String?
  private let cache = NSCache<NSURL, UIImage>()
  private var tasks: [URL: Task<UIImage?, Never>] = [:]
  private var generation = 0
  private var diagnosticEvents: [String] = []
  var diagnosticReport: String { diagnosticEvents.joined(separator: "\n") }
  private func record(_ message: String, url: URL) {
    diagnosticEvents.append(ReaderDiagnostics.address(url.absoluteString) + " | " + message)
    diagnosticEvents = Array(diagnosticEvents.suffix(40))
  }
  init(offlineThreadID: String? = nil) {
    self.offlineThreadID = offlineThreadID
    cache.totalCostLimit = 64 * 1024 * 1024; cache.countLimit = 80
  }
  func releaseCachedImages() {
    generation += 1
    diagnosticEvents.removeAll()
    tasks.values.forEach { $0.cancel() }
    tasks.removeAll()
    cache.removeAllObjects()
  }
  func load(_ url: URL, referer: URL? = nil) async -> UIImage? {
    if let image = cache.object(forKey: url as NSURL) { return image }
    if let task = tasks[url] { return await task.value }
    let epoch = generation
    let task = Task { () -> UIImage? in
      if let offlineThreadID {
        guard let file = try? await SouthOfflineStore.shared.repository.imageFile(url, threadID: offlineThreadID) else { return nil }
        return await Task.detached(priority: .utility) {
          guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2048,
                  kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary) else { return nil as UIImage? }
          return UIImage(cgImage: image)
        }.value
      }
      guard MediaPolicy.allowed(url) else { record("Rejected image URL", url: url); return nil }
      var request = URLRequest(url: url, timeoutInterval: 25)
      request.httpShouldHandleCookies = false
      request.setValue((referer ?? url.deletingLastPathComponent()).absoluteString, forHTTPHeaderField: "Referer")
      if let referer {
        request.setValue(SouthSitePolicy.sameOrigin(referer) ? BrowserIdentity.southDesktop : "Mozilla/5.0", forHTTPHeaderField: "User-Agent")
      }
      let config = URLSessionConfiguration.ephemeral
      config.httpCookieStorage = nil
      config.urlCredentialStorage = nil
      let session = URLSession(configuration: config)
      defer { session.finishTasksAndInvalidate() }
      let data: Data
      let response: URLResponse
      do { (data, response) = try await session.data(for: request) }
      catch {
        let value = error as NSError
        record("Network \(value.domain) code=\(value.code)", url: url)
        return nil
      }
      guard let http = response as? HTTPURLResponse else { record("Non-HTTP response", url: url); return nil }
      record("HTTP \(http.statusCode); MIME \(http.mimeType ?? "unknown"); bytes \(data.count)", url: url)
      guard (200..<300).contains(http.statusCode), data.count <= 32 * 1024 * 1024 else { return nil }
      let decoded = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil as UIImage? }
        return UIImage(cgImage: cgImage)
      }.value
      if decoded == nil { record("Image decode failed", url: url) }
      return decoded
    }
    tasks[url] = task
    let image = await task.value
    guard epoch == generation else { return nil }
    tasks.removeValue(forKey: url)
    if let image { cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4)) }
    return image
  }
}
struct RemoteImageView: View {
  @EnvironmentObject private var session: ForumSession
  @Environment(\.readerReferer) private var referer
  let url: URL?
  var originalURL: URL?
  var ratio: Double?
  var maximumHeight: CGFloat = 360
  var fillsFrame = false
  var openImage: ((ImageViewerSource) -> Void)?
  @State private var image: UIImage?
  @State private var loading = true
  @State private var attempt = 0
  @State private var imageURL: URL?
  // Reserve a stable preview box before decoding. Loading must not change a
  // tall post's height and fight the reader's in-flight scroll momentum.
  private var displayRatio: CGFloat { CGFloat(max(0.75, min(2.5, ratio ?? 1.5))) }
  var body: some View {
    Color(uiColor: .tertiarySystemFill)
      .aspectRatio(displayRatio, contentMode: .fit).frame(maxHeight: maximumHeight)
      .overlay {
        if let image {
          GeometryReader { bounds in
            Image(uiImage: image).resizable().aspectRatio(contentMode: fillsFrame ? .fill : .fit)
              .frame(width: bounds.size.width, height: bounds.size.height).clipped()
          }
        } else if loading { ProgressView() }
        else { Button(AppText.text("Retry image"), forumSymbol: "arrow.clockwise") { attempt += 1 }.appFont(.caption) }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .contentShape(Rectangle())
      .onTapGesture {
        if let image, let source = originalURL ?? url { openImage?(ImageViewerSource(preview: image, url: source)) }
      }
      .task(id: "\(url?.absoluteString ?? ""):\(attempt)") {
        // SwiftUI can restart this task after a full-screen viewer is dismissed.
        guard image == nil || imageURL != url else { return }
        imageURL = url
        loading = true
        image = nil
        let loaded = if let url { await session.images.load(url, referer: referer ?? session.site.base) } else { nil as UIImage? }
        guard !Task.isCancelled, imageURL == url else { return }
        image = loaded
        loading = false
      }
  }
}
struct ZoomImage: UIViewRepresentable {
  let image: UIImage
  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 5
    scroll.delegate = context.coordinator
    let view = UIImageView(image: image); view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
    ])
    context.coordinator.imageView = view
    let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
    tap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(tap)
    return scroll
  }
  func updateUIView(_ view: UIScrollView, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator: NSObject, UIScrollViewDelegate {
    weak var imageView: UIImageView?
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
      guard let scroll = gesture.view as? UIScrollView else { return }
      scroll.setZoomScale(scroll.zoomScale > 1 ? 1 : 2.5, animated: true)
    }
  }
}
