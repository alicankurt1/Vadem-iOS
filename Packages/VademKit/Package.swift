// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VademKit",
    defaultLocalization: "en",
    // macOS is listed so `swift test` runs business rules without a simulator.
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VademCore", targets: ["VademCore"]),
        .library(name: "VademPersistence", targets: ["VademPersistence"]),
        .library(name: "VademFeatures", targets: ["VademFeatures"]),
    ],
    targets: [
        // Pure domain: no UIKit, no SwiftUI, no SwiftData. Defines repository protocols.
        .target(name: "VademCore"),
        // The only module that imports SwiftData; implements VademCore's repository protocols.
        .target(name: "VademPersistence", dependencies: ["VademCore"]),
        .target(
            name: "VademFeatures",
            dependencies: ["VademCore", "VademPersistence"],
            resources: [.process("Resources")]
        ),
        // Shared test helpers and the PaymentRepository contract; used only by test targets.
        .target(name: "VademTestSupport", dependencies: ["VademCore"], path: "Sources/VademTestSupport"),
        .testTarget(name: "VademCoreTests", dependencies: ["VademCore", "VademTestSupport"]),
        .testTarget(name: "VademPersistenceTests", dependencies: ["VademPersistence", "VademTestSupport"]),
        .testTarget(
            name: "VademFeaturesTests",
            dependencies: ["VademFeatures", "VademCore"],
            exclude: ["Fixtures/generate-statement-fixtures.swift.txt"],
            // Uydurma ekstre PDF'i ve resmi (entegrasyon testi için).
            resources: [.copy("Fixtures/statement-sample.pdf"), .copy("Fixtures/statement-sample.png")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
