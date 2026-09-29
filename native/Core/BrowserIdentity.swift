import Foundation

enum BrowserIdentity {
  static func userAgent(for site: ForumSite, defaults: UserDefaults = .standard, systemVersion: String, isPad: Bool) -> String {
    let key = "forum_\(site.rawValue)_browser_user_agent"
    if let saved = defaults.string(forKey: key), isValid(saved) { return saved }
    let parts = systemVersion.split(separator: ".")
    let version = !parts.isEmpty && parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) })
      ? parts.joined(separator: "_") : "18_0"
    let platform = isPad ? "iPad; CPU OS" : "iPhone; CPU iPhone OS"
    // A stable app-controlled WebKit-compatible identity needs no web process or JavaScript.
    let value = "Mozilla/5.0 (\(platform) \(version) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    defaults.set(value, forKey: key)
    return value
  }

  private static func isValid(_ value: String) -> Bool {
    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 2048 &&
      value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value <= 126 }
  }
}
