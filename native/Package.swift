// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ForumCore",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "ForumCore", targets: ["ForumCore"])],
  dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9")],
  targets: [
    .target(name: "ForumCore", dependencies: ["SwiftSoup"], path: "Core"),
    .testTarget(name: "ForumCoreTests", dependencies: ["ForumCore"], path: "Tests")
  ]
)
