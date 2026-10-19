// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VademKit",
    defaultLocalization: "en",
    // macOS is listed so `swift test` runs business rules without a simulator.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VademCore", targets: ["VademCore"]),
        .library(name: "VademFeatures", targets: ["VademFeatures"]),
    ],
    targets: [
        // Pure domain: no UIKit, no SwiftUI, no SwiftData.
        .target(name: "VademCore"),
        .target(name: "VademFeatures", dependencies: ["VademCore"]),
        .testTarget(name: "VademCoreTests", dependencies: ["VademCore"]),
    ],
    swiftLanguageModes: [.v6]
)
