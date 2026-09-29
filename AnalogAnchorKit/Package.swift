// swift-tools-version: 5.9
import PackageDescription

// AnalogAnchorKit is the portable, platform-agnostic core of Analog Anchor (iOS).
// It contains no Android-derived system logic and no UI. It builds on Apple
// platforms (iOS 16+) and also compiles on Linux/macOS so domain logic can be
// unit-tested independently of Xcode.
let package = Package(
    name: "AnalogAnchorKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AnalogAnchorKit", targets: ["AnalogAnchorKit"])
    ],
    targets: [
        .target(
            name: "AnalogAnchorKit",
            path: "Sources/AnalogAnchorKit"
        ),
        .testTarget(
            name: "AnalogAnchorKitTests",
            dependencies: ["AnalogAnchorKit"],
            path: "Tests/AnalogAnchorKitTests"
        )
    ]
)
