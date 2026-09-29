import SwiftUI

// Inline Text images participate in the paragraph's line breaking, not the photo grid.
struct EmoticonText: View {
  let runs: [TextRun]
  @EnvironmentObject private var session: ForumSession
  @Environment(\.displayScale) private var displayScale
  @ScaledMetric(relativeTo: .body) private var side: CGFloat = 24
  @State private var images: [URL: UIImage] = [:]

  private var sources: [URL] {
    var seen = Set<URL>()
    return runs.compactMap(\.emoticon).filter { seen.insert($0).inserted }
  }
  var body: some View {
    paragraph.font(.body).lineSpacing(2).textSelection(.enabled)
      .fixedSize(horizontal: false, vertical: true)
      .task(id: sources) {
        for source in sources where images[source] == nil {
          let image = await session.images.load(source, referer: session.site.base)
          guard !Task.isCancelled else { return }
          if let image { images[source] = image }
        }
      }
  }
  private var paragraph: Text {
    runs.reduce(Text("")) { result, run in
      let part: Text
      if let source = run.emoticon, let image = images[source] {
        part = Text(Image(uiImage: compact(image))).baselineOffset(-3)
      } else if run.emoticon != nil {
        // A small text fallback never reserves a full photo-sized loading area.
        part = Text(Image(systemName: "face.smiling")).foregroundColor(.secondary)
      } else {
        var value = AttributedString(run.text)
        var intents: InlinePresentationIntent = []
        if run.bold { intents.insert(.stronglyEmphasized) }
        if run.italic { intents.insert(.emphasized) }
        value.inlinePresentationIntent = intents
        if let url = run.url { value.link = url; value.foregroundColor = .blue }
        part = Text(value)
      }
      return Text("\(result)\(part)")
    }
  }
  private func compact(_ image: UIImage) -> UIImage {
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { return image }
    let factor = min(1, side / longest)
    let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
    let format = UIGraphicsImageRendererFormat()
    format.scale = displayScale
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
