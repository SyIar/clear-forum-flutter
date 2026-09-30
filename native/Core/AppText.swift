import Foundation

enum AppText {
  static let locale = Locale(identifier: "zh_Hans")
  private static let bundle: Bundle = {
    guard let path = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
          let bundle = Bundle(path: path) else { return .main }
    return bundle
  }()

  // Localize only app-owned text at its source, never downloaded forum content.
  static func text(_ key: String) -> String {
    bundle.localizedString(forKey: key, value: key, table: "Localizable")
  }

  static func format(_ key: String, _ values: String...) -> String {
    String(format: text(key), locale: locale, arguments: values.map { $0 as CVarArg })
  }

  static func error(_ error: Error) -> String {
    if let error = error as? URLError {
      switch error.code {
      case .notConnectedToInternet, .networkConnectionLost:
        return text("Check your connection, then try again.")
      case .timedOut: return text("The request timed out. Please try again.")
      case .cancelled: return text("Canceled")
      default: return text("Could not connect to the server. Please try again.")
      }
    }
    if let error = error as? LocalizedError, let message = error.errorDescription { return message }
    return text("The operation could not be completed. Please try again.")
  }

  static func providerReason(_ reason: String) -> String {
    let pattern = #"^The provider returned HTTP ([0-9]{3})\. Open Web player if verification is required\.$"#
    if let expression = try? NSRegularExpression(pattern: pattern),
       let match = expression.firstMatch(in: reason, range: NSRange(reason.startIndex..., in: reason)),
       let range = Range(match.range(at: 1), in: reason) {
      return format("The provider returned HTTP %@. Open Web player if verification is required.", String(reason[range]))
    }
    return text(reason)
  }
}
