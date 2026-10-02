// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ArchiveSupport",
  platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "ArchiveSupport", targets: ["ArchiveSupport"])],
  dependencies: [.package(url: "https://github.com/ZipArchive/ZipArchive.git", exact: "2.6.0")],
  targets: [.target(name: "ArchiveSupport", dependencies: ["ZipArchive"], path: "Sources",
    linkerSettings: [.linkedLibrary("z")])]
)
