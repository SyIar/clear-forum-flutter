// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ImageCodecSupport",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "ImageCodecSupport", targets: ["ImageCodecSupport"])],
  dependencies: [.package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", exact: "1.6.0")],
  targets: [.target(name: "ImageCodecSupport", dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")],
    path: "Sources", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("z")])]
)
