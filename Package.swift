// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "NoteTune",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "NoteTune", path: "Sources/NoteTune")
    ]
)
