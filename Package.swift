// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fenetre",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "fenetre",
            path: "Sources/fenetre"
        )
    ],
    // Swift 5 language mode for the MVP: keeps strict-concurrency out of the
    // way of the Carbon C hotkey callback. We can revisit Swift 6 mode later.
    swiftLanguageModes: [.v5]
)
