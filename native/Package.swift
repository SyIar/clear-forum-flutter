// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ForumCore",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "ForumCore", targets: ["ForumCore"])],
  dependencies: [
    .package(path: "ImageCodecSupport"),
    .package(path: "ArchiveSupport"),
    .package(url: "https://github.com/ZipArchive/ZipArchive.git", exact: "2.6.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.9"),
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
  ],
  targets: [
    .target(name: "ForumCore", dependencies: ["SwiftSoup", "ArchiveSupport", "ImageCodecSupport"], path: "Core"),
    .testTarget(name: "ForumCoreTests", dependencies: ["ForumCore", "ZIPFoundation", "ZipArchive", "ImageCodecSupport"], path: "Tests")
  ]
)
