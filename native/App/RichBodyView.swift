import SwiftUI
import ImageIO

struct PostCard: View {
  let post: ForumPost
  let posters: PosterStore
  let navigate: (URL) -> Void
  let play: (BodyBlock) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Text(String(post.author.prefix(1)).uppercased()).font(.headline).foregroundStyle(.blue)
          .frame(width: 36, height: 36).background(.blue.opacity(0.12), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(post.author).font(.subheadline.bold())
          Text(post.date.replacingOccurrences(of: "T", with: " ").prefix(16)).font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if !post.number.isEmpty { Text(post.number).font(.caption.weight(.semibold)).foregroundStyle(.blue) }
      }
      Divider()
      RichBodyView(blocks: post.blocks, posters: posters, navigate: navigate, play: play)
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
      .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.05)))
  }
}

private struct BodyGroup: Identifiable {
  var id: UUID { blocks[0].id }
  let blocks: [BodyBlock]
}
struct RichBodyView: View {
  let blocks: [BodyBlock]
  let posters: PosterStore
  let navigate: (URL) -> Void
  let play: (BodyBlock) -> Void
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
    VStack(alignment: .leading, spacing: 10) {
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
    RemoteImageView(url: block.url, ratio: grid ? 1 : block.aspectRatio, maximumHeight: grid ? 180 : 360, opensViewer: true)
  }
  @ViewBuilder private func blockView(_ block: BodyBlock) -> some View {
    switch block.kind {
    case .paragraph:
      if let url = standaloneLink(block.runs) { CompactLink(url: url, label: block.runs.map(\.text).joined(), navigate: navigate) }
      else { Text(attributed(block.runs)).font(.body).lineSpacing(2).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    case .link:
      if let url = block.url { CompactLink(url: url, label: block.label, navigate: navigate) }
    case .media:
      MediaRow(block: block, posters: posters, play: play)
    case .quote:
      HStack(alignment: .top, spacing: 9) {
        RoundedRectangle(cornerRadius: 2).fill(.blue.opacity(0.4)).frame(width: 3)
        VStack(alignment: .leading, spacing: 6) {
          if !block.label.isEmpty { Text(block.label).font(.caption.bold()).foregroundStyle(.secondary) }
          AnyView(RichBodyView(blocks: block.children, posters: posters, navigate: navigate, play: play))
        }
      }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    case .spoiler:
      DisclosureGroup(block.label) {
        AnyView(RichBodyView(blocks: block.children, posters: posters, navigate: navigate, play: play)).padding(.top, 8)
      }.font(.subheadline)
    case .code:
      ScrollView(.horizontal) { Text(block.label).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(10) }
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    case .image: EmptyView()
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
      var part = AttributedString(run.text)
      var intents: InlinePresentationIntent = []
      if run.bold { intents.insert(.stronglyEmphasized) }
      if run.italic { intents.insert(.emphasized) }
      part.inlinePresentationIntent = intents
      if let url = run.url { part.link = url; part.foregroundColor = .blue }
      result.append(part)
    }
    return result
  }
}
struct CompactLink: View {
  let url: URL
  let label: String
  let navigate: (URL) -> Void
  var body: some View {
    Button { navigate(url) } label: {
      HStack(spacing: 5) {
        Image(systemName: "link").font(.system(size: 11))
        Text(label.isEmpty ? url.host ?? "Link" : label).font(.caption).lineLimit(1).truncationMode(.middle)
        Image(systemName: "arrow.up.right").font(.system(size: 9))
      }.padding(.horizontal, 8).padding(.vertical, 5)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.blue.opacity(0.14)))
    }.buttonStyle(.plain).foregroundStyle(.blue)
      .accessibilityLabel(label.isEmpty ? url.absoluteString : label)
  }
}
struct MediaRow: View {
  let block: BodyBlock
  let posters: PosterStore
  let play: (BodyBlock) -> Void
  @EnvironmentObject private var session: ForumSession
  @State private var poster: URL?
  @State private var fetching = true
  var body: some View {
    HStack(spacing: 10) {
      ZStack {
        Color(uiColor: .tertiarySystemFill)
        if let poster { RemoteImageView(url: poster, ratio: 4 / 3, maximumHeight: 84, opensViewer: false) }
        else if fetching { ProgressView() }
        else { Image(systemName: "film").foregroundStyle(.secondary) }
      }.frame(width: 108, height: 84).clipShape(RoundedRectangle(cornerRadius: 12))
      Button { play(block) } label: {
        VStack(alignment: .leading, spacing: 8) {
          Text(block.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          Text("Tap to play").font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
        }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
          .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1)))
      }.buttonStyle(.plain).disabled(block.url == nil)
    }.task(id: block.url) { fetching = true; poster = await posters.resolve(block, session: session); fetching = false }
  }
}

@MainActor
final class ImageStore {
  static let shared = ImageStore()
  private let cache = NSCache<NSURL, UIImage>()
  private var tasks: [URL: Task<UIImage?, Never>] = [:]
  init() { cache.totalCostLimit = 64 * 1024 * 1024; cache.countLimit = 80 }
  func load(_ url: URL) async -> UIImage? {
    if let image = cache.object(forKey: url as NSURL) { return image }
    if let task = tasks[url] { return await task.value }
    let task = Task { () -> UIImage? in
      guard MediaPolicy.allowed(url) else { return nil }
      var request = URLRequest(url: url, timeoutInterval: 25)
      request.httpShouldHandleCookies = false
      request.setValue(url.deletingLastPathComponent().absoluteString, forHTTPHeaderField: "Referer")
      let config = URLSessionConfiguration.ephemeral
      config.httpCookieStorage = nil
      config.urlCredentialStorage = nil
      let session = URLSession(configuration: config)
      defer { session.finishTasksAndInvalidate() }
      guard let (data, response) = try? await session.data(for: request), let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode), data.count <= 32 * 1024 * 1024 else { return nil }
      return await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil as UIImage? }
        return UIImage(cgImage: cgImage)
      }.value
    }
    tasks[url] = task
    let image = await task.value
    tasks.removeValue(forKey: url)
    if let image { cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4)) }
    return image
  }
}
struct RemoteImageView: View {
  let url: URL?
  var ratio: Double?
  var maximumHeight: CGFloat = 360
  var opensViewer = false
  @State private var image: UIImage?
  @State private var loading = true
  @State private var showing = false
  @State private var attempt = 0
  private var displayRatio: CGFloat { max(0.75, min(2.5, ratio ?? image.map { $0.size.width / max(1, $0.size.height) } ?? 1.5)) }
  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: maximumHeight)
          .contentShape(Rectangle()).onTapGesture { if opensViewer { showing = true } }
      } else {
        ZStack {
          Color(uiColor: .tertiarySystemFill)
          if loading { ProgressView() }
          else { Button("Retry image", systemImage: "arrow.clockwise") { attempt += 1 }.font(.caption) }
        }.aspectRatio(displayRatio, contentMode: .fit).frame(maxHeight: maximumHeight)
      }
    }.clipShape(RoundedRectangle(cornerRadius: 10))
      .task(id: "\(url?.absoluteString ?? ""):\(attempt)") {
        loading = true
        image = nil
        if let url { image = await ImageStore.shared.load(url) }
        loading = false
      }
      .fullScreenCover(isPresented: $showing) {
        NavigationStack {
          if let image { ZoomImage(image: image).background(.black).ignoresSafeArea(edges: .bottom)
            .toolbar {
              ToolbarItem(placement: .topBarLeading) { Button("Back", systemImage: "chevron.backward") { showing = false } }
              ToolbarItem(placement: .topBarTrailing) { ShareLink(item: Image(uiImage: image), preview: SharePreview("Image", image: Image(uiImage: image))) }
            }
          }
        }.background(MediaEdgeBack { showing = false }).preferredColorScheme(.dark)
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
