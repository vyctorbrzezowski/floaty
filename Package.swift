// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Floaty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Floaty", targets: ["Floaty"])
    ],
    targets: [
        .executableTarget(
            name: "Floaty"
        )
    ]
)
