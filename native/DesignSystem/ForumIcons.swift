import SwiftUI
import UIKit

private final class ForumAssetLocator: NSObject {}

// Keep semantic names stable at call sites. The rendered artwork is exclusively
// Pika SVG, including UIKit buttons and labels that cannot host a SwiftUI view.
public enum ForumIcons {
  private static let bundle = Bundle(for: ForumAssetLocator.self)
  private static let names: [String: String] = {
    guard let url = bundle.url(forResource: "PikaSymbolMap", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let value = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return value
  }()

  public static func image(_ symbol: String) -> UIImage {
    let name = names[symbol] ?? "question-mark-circle"
    return (UIImage(named: name, in: bundle, compatibleWith: nil) ?? UIImage()).withRenderingMode(.alwaysTemplate)
  }
}

public extension Image {
  init(forumSymbol: String) {
    self.init(uiImage: ForumIcons.image(forumSymbol))
  }
}

public extension Label where Title == Text, Icon == Image {
  init(_ title: String, forumSymbol: String) {
    self.init { Text(title) } icon: { Image(forumSymbol: forumSymbol) }
  }
}

public extension Button where Label == SwiftUI.Label<Text, Image> {
  init(_ title: String, forumSymbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
    self.init(role: role, action: action) { SwiftUI.Label(title, forumSymbol: forumSymbol) }
  }
}

public struct ForumUnavailableView: View {
  let title: String
  let symbol: String
  let description: Text?
  public init(_ title: String, forumSymbol: String, description: Text? = nil) {
    self.title = title; self.symbol = forumSymbol; self.description = description
  }
  public var body: some View {
    ContentUnavailableView {
      Label { Text(title) } icon: {
        Image(forumSymbol: symbol).resizable().scaledToFit().frame(width: 48, height: 48)
      }
    } description: {
      description
    }
  }
}
