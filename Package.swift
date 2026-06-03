// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LyricFloater",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LyricFloater", targets: ["LyricFloater"])
    ],
    targets: [
        .executableTarget(
            name: "LyricFloater"
        )
    ]
)
