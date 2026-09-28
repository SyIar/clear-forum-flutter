import Flutter
import UIKit

final class NativeGlassFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let prefix: String
  init(messenger: FlutterBinaryMessenger, prefix: String) {
    self.messenger = messenger
    self.prefix = prefix
    super.init()
  }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    NativeGlassPlatformView(frame: frame, id: viewId, args: args as? [String: Any] ?? [:],
                            messenger: messenger, prefix: prefix)
  }
}

private final class NativeGlassPlatformView: NSObject, FlutterPlatformView {
  private let host: NativeGlassHost
  private let channel: FlutterMethodChannel
  init(frame: CGRect, id: Int64, args: [String: Any], messenger: FlutterBinaryMessenger, prefix: String) {
    channel = FlutterMethodChannel(name: "\(prefix)/glass/\(id)", binaryMessenger: messenger)
    host = NativeGlassHost(frame: frame, kind: args["kind"] as? String ?? "toolbar")
    super.init()
    host.onAction = { [weak self] id in self?.channel.invokeMethod("action", arguments: id) }
    host.update(args)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let values = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.host.update(values)
      result(nil)
    }
  }
  func view() -> UIView { host }
  deinit { channel.setMethodCallHandler(nil) }
}

private final class NativeGlassHost: UIView, UITabBarDelegate {
  var onAction: ((String) -> Void)?
  private let kind: String
  private let toolbar = UIToolbar()
  private let tabBar = UITabBar()
  private let button = UIButton(type: .system)
  private var actions: [[String: Any]] = []
  private var itemIDs: [String] = []
  private var textScale: CGFloat = 1
  private var accent = UIColor.systemBlue

  init(frame: CGRect, kind: String) {
    self.kind = kind
    super.init(frame: frame)
    backgroundColor = .clear
    clipsToBounds = false
    if kind == "tabs" {
      tabBar.delegate = self
      tabBar.itemPositioning = .fill
      addSubview(tabBar)
    } else if kind == "button" {
      addSubview(button)
      button.addTarget(self, action: #selector(pressed), for: .touchUpInside)
    } else {
      addSubview(toolbar)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  override func layoutSubviews() {
    super.layoutSubviews()
    if kind == "tabs" { tabBar.frame = bounds }
    else if kind == "button" { button.frame = bounds }
    else { toolbar.frame = bounds }
  }

  func update(_ args: [String: Any]) {
    overrideUserInterfaceStyle = (args["dark"] as? Bool ?? false) ? .dark : .light
    isHidden = !(args["visible"] as? Bool ?? true)
    textScale = max(0.8, min(3, CGFloat(args["textScale"] as? Double ?? 1)))
    if let argb = args["tint"] as? NSNumber {
      let value = argb.uint32Value
      accent = UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255,
                       alpha: CGFloat((value >> 24) & 255) / 255)
      tabBar.tintColor = accent
    }
    actions = args["actions"] as? [[String: Any]] ?? []
    if kind == "tabs" { updateTabs(args) }
    else if kind == "button" { updateButton() }
    else { updateToolbar(title: args["title"] as? String ?? "") }
    setNeedsLayout()
  }

  private func image(_ action: [String: Any]) -> UIImage? {
    UIImage(systemName: action["symbol"] as? String ?? "")
  }
  private func emit(_ action: [String: Any]) {
    guard !isHidden, action["enabled"] as? Bool == true, let id = action["id"] as? String else { return }
    onAction?(id)
  }
  private func menu(_ action: [String: Any]) -> UIMenu? {
    guard let entries = action["menu"] as? [[String: Any]], !entries.isEmpty else { return nil }
    return UIMenu(children: entries.map { item in
      var attributes: UIMenuElement.Attributes = []
      if item["enabled"] as? Bool != true { attributes.insert(.disabled) }
      if item["destructive"] as? Bool == true { attributes.insert(.destructive) }
      return UIAction(title: item["label"] as? String ?? "", image: image(item),
                      attributes: attributes,
                      state: item["selected"] as? Bool == true ? .on : .off) { [weak self] _ in
        self?.emit(item)
      }
    })
  }

  private func updateToolbar(title: String) {
    var items: [UIBarButtonItem] = []
    for (index, action) in actions.enumerated() {
      if index == 1 && !title.isEmpty {
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
        let label = UILabel()
        label.text = title
        label.textColor = .label
        label.font = .systemFont(ofSize: 15 * textScale, weight: .semibold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.accessibilityTraits = .staticText
        label.sizeToFit()
        items.append(UIBarButtonItem(customView: label))
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
      } else if index == 1 && actions.first?["showLabel"] as? Bool == true {
        items.append(UIBarButtonItem(systemItem: .flexibleSpace))
      }
      let callback = UIAction { [weak self] _ in self?.emit(action) }
      let item = UIBarButtonItem(title: action["showLabel"] as? Bool == true ? action["label"] as? String : nil,
                                image: image(action), primaryAction: callback, menu: menu(action))
      item.isEnabled = action["enabled"] as? Bool ?? false
      item.accessibilityLabel = action["label"] as? String
      item.tintColor = action["selected"] as? Bool == true ? accent : .label
      items.append(item)
    }
    toolbar.setItems(items, animated: false)
  }

  private func updateButton() {
    guard let action = actions.first else { button.isHidden = true; return }
    button.isHidden = false
    var config: UIButton.Configuration
    if #available(iOS 26.0, *) { config = .glass() }
    else { config = .gray() }
    config.cornerStyle = .capsule
    config.image = image(action)
    config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .medium)
    config.baseForegroundColor = action["selected"] as? Bool == true ? accent : .label
    config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    if action["showLabel"] as? Bool == true {
      config.title = action["label"] as? String
      config.imagePadding = 6
    }
    button.configuration = config
    button.isEnabled = action["enabled"] as? Bool ?? false
    button.accessibilityLabel = action["label"] as? String
    button.menu = menu(action)
    button.showsMenuAsPrimaryAction = button.menu != nil
  }
  @objc private func pressed() {
    guard button.menu == nil, let action = actions.first else { return }
    emit(action)
  }

  private func updateTabs(_ args: [String: Any]) {
    let ids = actions.compactMap { $0["id"] as? String }
    if ids != itemIDs {
      itemIDs = ids
      tabBar.setItems(actions.enumerated().map { index, action in
        UITabBarItem(title: action["label"] as? String, image: image(action), tag: index)
      }, animated: false)
    }
    for (index, item) in (tabBar.items ?? []).enumerated() where index < actions.count {
      item.title = actions[index]["label"] as? String
      item.image = image(actions[index])
      item.isEnabled = actions[index]["enabled"] as? Bool ?? false
      item.accessibilityLabel = item.title
    }
    let selected = args["selectedIndex"] as? Int ?? 0
    if let items = tabBar.items, items.indices.contains(selected) { tabBar.selectedItem = items[selected] }
  }
  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard actions.indices.contains(item.tag) else { return }
    emit(actions[item.tag])
  }
}

