import Foundation

enum DownloadLink: Hashable {
  case gofile(URL)
  case hosted(URL)
  case unsupported(URL)

  static func parse(_ input: String) -> Self? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value.utf8.count <= 8192,
          value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
          var parts = URLComponents(string: value),
          let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
          let original = parts.url else { return nil }
    // Only known download providers are upgraded; arbitrary links remain unchanged.
    parts.scheme = "https"
    if scheme == "http", parts.port == 80 { parts.port = nil }
    if let candidate = parts.url, candidate.port == nil || candidate.port == 443 {
      if let page = GofilePolicy.pageURL(candidate) { return .gofile(page) }
      if HostedFilePolicy.provider(candidate) != nil { return .hosted(candidate) }
    }
    return .unsupported(original)
  }
}
