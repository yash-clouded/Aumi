// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aumi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Aumi", targets: ["Aumi"])
    ],
    dependencies: [
        // Starscream for WebSocket fallback
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Aumi",
            dependencies: ["Starscream"],
            path: "Aumi"
        )
    ]
)
