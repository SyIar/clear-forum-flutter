import SwiftUI

// Inline Text images participate in the paragraph's line breaking, not the photo grid.
struct EmoticonText: View {
  let runs: [TextRun]
  @ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17
  @EnvironmentObject private var session: ForumSession
  @Environment(\.displayScale) private var displayScale
  @ScaledMetric(relativeTo: .body) private var height: CGFloat = 24
  @State private var images: [URL: UIImage] = [:]

  private var sources: [URL] {
    var seen = Set<URL>()
    return runs.compactMap(\.emoticon).filter { seen.insert($0).inserted }
  }
  var body: some View {
    paragraph.forumFont(.body).lineSpacing(2).textSelection(.enabled)
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
        part = Text(Image(uiImage: inlineImage(image))).baselineOffset(-3)
      } else if run.emoticon != nil {
        // A small text fallback never reserves a full photo-sized loading area.
        part = Text(Image(systemName: "face.smiling")).foregroundColor(.secondary)
      } else {
        part = Text(AppTypography.richText(run, size: textSize))
      }
      return Text("\(result)\(part)")
    }
  }
  private func inlineImage(_ image: UIImage) -> UIImage {
    guard image.size.width > 0, image.size.height > 0 else { return image }
    // Use a consistent height; wide emoticons keep their natural aspect ratio.
    let size = CGSize(width: height * image.size.width / image.size.height, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = displayScale
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
  }
}
