// swift-tools-version: 5.9
import PackageDescription
let package = Package(
  name: "TiebaCore", platforms: [.macOS(.v13), .iOS(.v17)],
  products: [.library(name: "TiebaCore", targets: ["TiebaCore"])],
  dependencies: [.package(url: "https://github.com/apple/swift-protobuf.git", exact: "1.38.1")],
  targets: [
    .target(name: "TiebaCore", dependencies: [.product(name: "SwiftProtobuf", package: "swift-protobuf")], path: "Core"),
    .testTarget(name: "TiebaCoreTests", dependencies: ["TiebaCore"], path: "Tests", resources: [.copy("Fixtures")])
  ]
)
