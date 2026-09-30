import SwiftUI
import AVKit
import Photos
import Network
import CryptoKit
import ImageIO

@MainActor final class PictureCache: ObservableObject {
  static let shared = PictureCache()
  private let cache = NSCache<NSURL, UIImage>()
  private let network: URLSession
  private let monitor = NWPathMonitor()
  @Published var wifi = true
  private var tasks: [URL: Task<UIImage?, Never>] = [:]
  let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TiebaImages")
  init() {
    cache.totalCostLimit = 80 * 1024 * 1024
    let config = URLSessionConfiguration.ephemeral; config.httpCookieStorage = nil; config.urlCredentialStorage = nil; config.timeoutIntervalForRequest = 25
    network = URLSession(configuration: config)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.wifi = path.usesInterfaceType(.wifi) } }
    monitor.start(queue: DispatchQueue(label: "TiebaLite.network"))
  }
  func file(_ url: URL) -> URL { folder.appendingPathComponent(SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()) }
  var bytes: Int { (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]))?.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } ?? 0 }
  func clear() throws {
    tasks.values.forEach { $0.cancel() }; tasks.removeAll(); cache.removeAllObjects()
    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: file) }
  }
  func load(_ url: URL) async -> UIImage? {
    if let image = cache.object(forKey: url as NSURL) { return image }
    if let task = tasks[url] { return await task.value }
    let target = file(url)
    let task = Task<UIImage?, Never> {
      var data = try? Data(contentsOf: target)
      if data == nil {
        var request = URLRequest(url: url); request.setValue("https://tieba.baidu.com/", forHTTPHeaderField: "Referer"); request.httpShouldHandleCookies = false
        guard let (bytes, response) = try? await network.data(for: request), let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), bytes.count <= 32 * 1024 * 1024, !Task.isCancelled else { return nil }
        data = bytes
      }
      guard let data else { return nil }
      let image = await Task.detached(priority: .utility) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil as UIImage? }
        return UIImage(cgImage: cg)
      }.value
      if image != nil && !FileManager.default.fileExists(atPath: target.path) { try? data.write(to: target, options: .atomic) }
      return image
    }
    tasks[url] = task; let image = await task.value; tasks.removeValue(forKey: url)
    if let image { cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4)) }
    return image
  }
}

struct RemotePicture: View {
  let url: URL
  let thumbnail: URL?
  var preview = false
  var open: (() -> Void)? = nil
  @EnvironmentObject private var settings: Preferences
  @Environment(\.colorScheme) private var scheme
  @ObservedObject private var cache = PictureCache.shared
  @State private var image: UIImage?
  @State private var loading = false
  @State private var manual = false
  @State private var attempt = 0
  @State private var showing = false
  private var automatic: Bool { settings.text("imageLoadType") != "3" && (settings.text("imageLoadType") != "1" || cache.wifi) }
  private var source: URL { settings.text("imageLoadType") == "2" || cache.wifi || manual ? url : thumbnail ?? url }
  var body: some View {
    Group {
      if let image {
        Group {
          if preview {
            GeometryReader { geometry in
              Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.frame(height: 88)
          } else {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 460)
              .onTapGesture { if let open { open() } else { showing = true } }
          }
        }.opacity(scheme == .dark && settings.flag("imageDarkenWhenNightMode") ? 0.8 : 1)
      } else {
        ZStack {
          Color(uiColor: .tertiarySystemFill)
          if loading { ProgressView() }
          else if preview { Image(systemName: "photo").foregroundStyle(Color(uiColor: .secondaryLabel)) }
          else { Button(tr(manual || automatic ? "retry" : "tapToLoad"), systemImage: "photo") { manual = true; attempt += 1 }.tiebaFont(.caption) }
        }.frame(height: preview ? 88 : 160)
      }
    }.clipShape(RoundedRectangle(cornerRadius: 10))
      .task(id: "\(source):\(attempt):\(automatic)") {
        guard automatic || manual else { return }; loading = true; image = await cache.load(source); loading = false
      }.fullScreenCover(isPresented: $showing) { ImageGallery(urls: [url]) }
  }
}

struct ImageGallery: View {
  let urls: [URL]
  var initialIndex = 0
  @Environment(\.dismiss) private var dismiss
  @State private var selection = 0
  @State private var images: [URL: UIImage] = [:]
  @State private var error: String?
  var body: some View {
    NavigationStack {
      TabView(selection: $selection) {
        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
          Group {
            if let image = images[url] { ZoomPicture(image: image) }
            else { ProgressView().task {
              _ = await PictureCache.shared.load(url)
              if let data = try? Data(contentsOf: PictureCache.shared.file(url)), let full = UIImage(data: data) { images[url] = full }
            } }
          }.tag(index)
        }
      }.tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never)).background(.black).ignoresSafeArea(edges: .bottom)
        .toolbar {
          ToolbarItem(placement: .topBarLeading) { Button(tr("back"), systemImage: "chevron.left") { dismiss() } }
          ToolbarItemGroup(placement: .topBarTrailing) {
            if urls.indices.contains(selection), let image = images[urls[selection]] {
              Button(tr("saveImage"), systemImage: "square.and.arrow.down") { Task { await save(urls[selection]) } }
              ShareLink(item: Image(uiImage: image), preview: SharePreview(tr("media"), image: Image(uiImage: image)))
            }
          }
        }
    }.background(MediaEdgeBack { dismiss() })
      .preferredColorScheme(.dark).onAppear { selection = initialIndex }.alert(tr("saveImage"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(tr("done")) {} } message: { Text(error ?? "") }
  }
  private func save(_ url: URL) async {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { error = tr("saveImageViaShare"); return }
    let file = PictureCache.shared.file(url)
    do { try await PHPhotoLibrary.shared().performChanges { PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil) }; error = tr("imageSaved") }
    catch { self.error = error.localizedDescription }
  }
}
struct ZoomPicture: UIViewRepresentable {
  let image: UIImage
  func makeUIView(context: Context) -> UIScrollView {
    let scroll = UIScrollView(); scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6; scroll.delegate = context.coordinator
    let view = UIImageView(image: image); view.contentMode = .scaleAspectFit; view.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(view)
    NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor), view.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)])
    context.coordinator.image = view
    let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.zoom(_:))); tap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(tap)
    return scroll
  }
  func updateUIView(_ view: UIScrollView, context: Context) {}
  func makeCoordinator() -> Coordinator { Coordinator() }
  final class Coordinator: NSObject, UIScrollViewDelegate {
    weak var image: UIImageView?
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { image }
    @objc func zoom(_ tap: UITapGestureRecognizer) { if let view = tap.view as? UIScrollView { view.setZoomScale(view.zoomScale > 1 ? 1 : 3, animated: true) } }
  }
}

struct NativePlayer: View {
  let url: URL
  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?
  var body: some View {
    NavigationStack {
      VideoPlayer(player: player).ignoresSafeArea(edges: .bottom).background(.black)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("back"), systemImage: "chevron.left") { dismiss() } }; ToolbarItem(placement: .topBarTrailing) { Button(tr("refresh"), systemImage: "arrow.clockwise") { load() } } }
    }.background(MediaEdgeBack { player?.pause(); dismiss() })
      .onAppear(perform: load).onDisappear { player?.pause(); player = nil }.preferredColorScheme(.dark)
  }
  private func load() { player?.pause(); player = AVPlayer(url: url); player?.play() }
}

enum Emoticons {
  static var catalog: [String: String] = {
    var values: [String: String] = [:]
    if let url = TiebaResources.bundle.url(forResource: "emoticons_zh", withExtension: "arb"), let data = try? Data(contentsOf: url), let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] { values = map.filter { valid($0.key, $0.value) } }
    if let source = UserDefaults.standard.string(forKey: "flutter.tieba_lite.emoticons.learned.v1"), let data = source.data(using: .utf8), let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] { values.merge(map.filter { valid($0.key, $0.value) }) { old, _ in old } }
    return values
  }()
  static func valid(_ id: String, _ name: String) -> Bool { id.range(of: "^image_emoticon[1-9][0-9]{0,3}$", options: .regularExpression) != nil && !name.isEmpty && name.count <= 48 && name.rangeOfCharacter(from: CharacterSet(charactersIn: "()#\r\n")) == nil }
  static func image(_ id: String) -> UIImage? {
    let id = id == "image_emoticon" ? "image_emoticon1" : id
    for suffix in ["webp", "png"] { if let url = TiebaResources.bundle.url(forResource: id, withExtension: suffix, subdirectory: "emoticons"), let image = UIImage(contentsOfFile: url.path) { return image } }
    return nil
  }
  static func learn(_ parts: [ContentPart]) {
    var changed = false
    for part in parts where part.type == 2 && valid(part.sourceID, part.caption) && catalog[part.sourceID] == nil && catalog.count < 1024 { catalog[part.sourceID] = part.caption; changed = true }
    if changed, let data = try? JSONSerialization.data(withJSONObject: catalog) { UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: "flutter.tieba_lite.emoticons.learned.v1") }
  }
}

struct RichContent: View {
  @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 16
  let parts: [ContentPart]
  @EnvironmentObject private var settings: Preferences
  @State private var playback: URL?
  @State private var gallery: URL?
  private var groups: [[ContentPart]] {
    var output: [[ContentPart]] = []
    for part in parts {
      let inline = [0, 1, 2, 4, 9, 27].contains(part.type)
      if inline, let previous = output.last?.last, [0, 1, 2, 4, 9, 27].contains(previous.type) { output[output.count - 1].append(part) }
      else { output.append([part]) }
    }
    return output
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
        if let part = group.first {
          if [0, 1, 2, 4, 9, 27].contains(part.type) { inline(group).textSelection(.enabled).lineSpacing(2).fixedSize(horizontal: false, vertical: true) }
          else if [3, 20].contains(part.type), !settings.flag("hideMedia"), let url = part.url { RemotePicture(url: url, thumbnail: part.thumbnail, open: { gallery = url }) }
          else if [5, 10].contains(part.type), !settings.flag("hideMedia"), let url = part.url {
            Button { playback = url } label: { Label(tr(part.type == 10 ? "audio" : "video"), systemImage: "play.circle.fill").frame(maxWidth: .infinity, alignment: .leading).padding(12) }.buttonStyle(.glass)
          } else if !part.text.isEmpty { Text(part.text).foregroundStyle(.secondary) }
        }
      }
    }.onAppear { Emoticons.learn(parts) }
      .fullScreenCover(item: Binding(get: { playback.map(URLItem.init) }, set: { playback = $0?.url })) { NativePlayer(url: $0.url) }
      .fullScreenCover(item: Binding(get: { gallery.map(URLItem.init) }, set: { gallery = $0?.url })) { item in
        let urls = parts.filter { [3, 20].contains($0.type) }.compactMap(\.url)
        ImageGallery(urls: urls, initialIndex: urls.firstIndex(of: item.url) ?? 0)
      }
  }
  private func inline(_ parts: [ContentPart]) -> Text {
    parts.reduce(Text("")) { accumulated, part in
      if part.type == 2, let image = Emoticons.image(part.sourceID) {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)); let scaled = renderer.image { _ in image.draw(in: CGRect(x: 0, y: 0, width: 24, height: 24)) }
        return accumulated + Text(Image(uiImage: scaled)).baselineOffset(-4)
      }
      var text = AttributedString(part.text)
      text.font = Font(MixedScriptFont.font(size: textSize * settings.fontScale, bold: false))
      if part.type == 1 { text.link = part.url; text.foregroundColor = .blue }
      if part.type == 4, !part.sourceID.isEmpty { text.link = URL(string: "tblite://user?uid=\(part.sourceID)"); text.foregroundColor = .blue }
      return accumulated + Text(text)
    }
  }
}
struct URLItem: Identifiable { let url: URL; var id: String { url.absoluteString } }
