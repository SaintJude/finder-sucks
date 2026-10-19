// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FinderSucks",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FinderSucks", path: "Sources/FinderSucks")
    ]
)
