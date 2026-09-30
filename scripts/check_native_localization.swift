import Foundation

let source = URL(fileURLWithPath: "native/Resources/zh-Hans.lproj", isDirectory: true)
guard let bundle = Bundle(url: source) else { fatalError("Missing Chinese localization bundle") }
let download = bundle.localizedString(forKey: "Download all", value: nil, table: "Localizable")
guard download == "\u{5168}\u{90E8}\u{4E0B}\u{8F7D}" else { fatalError("Chinese string lookup failed") }
let page = bundle.localizedString(forKey: "Page %@", value: nil, table: "Localizable")
guard String(format: page, "48") == "\u{7B2C} 48 \u{9875}" else { fatalError("Chinese interpolation failed") }
let filename = "100% %@ original.zip"
let action = bundle.localizedString(forKey: "Download %@", value: nil, table: "Localizable")
guard String(format: action, filename).hasSuffix(filename) else { fatalError("User file name was changed by formatting") }
print("Validated Foundation Chinese lookup, page interpolation, and literal file-name preservation")
