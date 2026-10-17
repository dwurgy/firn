// swift-tools-version: 6.0
import PackageDescription

// Firn's logic, kept out of the Xcode project so it builds and tests from the
// command line (`swift build`, `swift test`) and can later be shared with iOS.
let package = Package(
    name: "FirnCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FirnCore", targets: ["FirnCore"]),
    ],
    targets: [
        .target(name: "FirnCore"),
        .testTarget(name: "FirnCoreTests", dependencies: ["FirnCore"]),
    ]
)
