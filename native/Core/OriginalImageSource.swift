import Foundation
import SwiftSoup

enum OriginalImageSource {
  static func resolve(_ node: Element, page: URL, preview: URL, link: URL?) -> URL {
    for name in ["data-original", "data-full-src", "data-full-url", "data-url"] {
      if let value = try? node.attr(name), let url = SimpSitePolicy.resolve(value, from: page) { return url }
    }
    // Only explicit image links are originals. An image-host landing page is not.
    if let link, ["jpg", "jpeg", "png", "gif", "webp", "heic", "avif"].contains(link.pathExtension.lowercased()) { return link }
    return preview
  }
}
