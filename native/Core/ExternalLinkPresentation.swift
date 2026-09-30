import Foundation

enum ExternalLinkPresentation {
  struct Segment: Identifiable {
    let id: Int
    let runs: [TextRun]
    var url: URL?
    var label: String { runs.map(\.text).joined() }
  }

  // Split only for presentation. Original parsed runs, destinations and cache
  // identities remain intact; styled pieces of one anchor form one chip.
  static func segments(_ runs: [TextRun], site: ForumSite) -> [Segment] {
    var result: [Segment] = [], pending: [TextRun] = []
    var target: URL?
    func flush() {
      guard !pending.isEmpty else { return }
      if pending.contains(where: { $0.emoticon != nil || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
        result.append(Segment(id: result.count, runs: pending, url: target))
      }
      pending = []
    }
    for run in runs {
      let external = run.url.flatMap { isExternal($0, site: site) && run.emoticon == nil ? $0 : nil }
      if external != target { flush(); target = external }
      pending.append(run)
    }
    flush()
    return result
  }

  static func isExternal(_ url: URL, site: ForumSite) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "") && !site.sameOrigin(url)
  }

  static func title(url: URL, label: String, site: ForumSite) -> String {
    let clean = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard isExternal(url, site: site) else { return clean.isEmpty ? url.host ?? AppText.text("Link") : clean }
    let prefix = providerLabel(url)
    let raw = clean.lowercased()
    let usesAddress = clean.isEmpty || raw.hasPrefix("https://") || raw.hasPrefix("http://") ||
      raw.hasPrefix("www.") || raw == url.host?.lowercased()
    let name = usesAddress ? (url.lastPathComponent.isEmpty ? AppText.text("Open link") : url.lastPathComponent) : clean
    return prefix + "## " + name
  }

  private static func providerLabel(_ url: URL) -> String {
    // Scheme normalization here is for the visible name only, never navigation.
    var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    parts?.scheme = "https"; parts?.port = nil
    if let candidate = parts?.url, let host = HostedFilePolicy.hostProvider(candidate) { return host.rawValue }
    let host = HostedFilePolicy.siteHost(url)
    let labels = host.split(separator: ".")
    if labels.count == 2, ["gofile", "mega", "cyberdrop", "cyberfile", "mediafire", "1fichier", "dropbox", "terabox", "krakenfiles", "rapidgator"].contains(String(labels[0])) {
      return String(labels[0])
    }
    return host.isEmpty ? "link" : host
  }
}
