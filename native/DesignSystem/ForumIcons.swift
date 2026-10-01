import SwiftUI
import UIKit

private final class ForumAssetLocator: NSObject {}

// Keep semantic names stable at call sites. The rendered artwork is exclusively
// Pika SVG, including UIKit buttons and labels that cannot host a SwiftUI view.
public enum ForumIcons {
  private static let bundle = Bundle(for: ForumAssetLocator.self)
  private static let resized = NSCache<NSString, UIImage>()
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
  public static func image(_ symbol: String, size: CGFloat) -> UIImage {
    let key = "\(symbol):\(size)" as NSString
    if let cached = resized.object(forKey: key) { return cached }
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let result = UIGraphicsImageRenderer(size: bounds.size).image { _ in
      image(symbol).draw(in: bounds)
    }.withRenderingMode(.alwaysTemplate)
    resized.setObject(result, forKey: key)
    return result
  }
}

public extension Image {
  init(forumSymbol: String, size: CGFloat? = nil) {
    self.init(uiImage: size.map { ForumIcons.image(forumSymbol, size: $0) } ?? ForumIcons.image(forumSymbol))
  }
}

// Buttons and menus share a fixed icon canvas and touch target in native toolbars.
public struct ForumToolbarIcon: View {
  private let symbol: String
  public init(_ symbol: String) { self.symbol = symbol }
  public var body: some View {
    Image(forumSymbol: symbol, size: 22)
      .frame(width: 44, height: 44).contentShape(Rectangle())
  }
}

// Host the whole cluster in one ToolbarItem so UIKit cannot space a Menu
// differently from a Button. Each child owns the same 44-point column.
public struct ForumToolbarGroup<Content: View>: View {
  private let content: () -> Content
  public init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
  public var body: some View {
    HStack(spacing: 0, content: content)
      .buttonStyle(.plain).tint(.blue)
      .padding(.horizontal, 6).padding(.vertical, 2)
      .glassEffect(.regular.interactive(), in: .capsule)
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
