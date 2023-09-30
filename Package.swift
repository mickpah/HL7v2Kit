// swift-tools-version: 6.0
// HL7v2Kit — HL7 v2.x parser, builder, and validator for Swift.
// Apache 2.0 licensed. See LICENSE.

import PackageDescription

let package = Package(
    name: "HL7v2Kit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "HL7v2Kit", targets: ["HL7v2Kit"]),
        .library(name: "HL7v2KitDictionaries", targets: ["HL7v2KitDictionaries"]),
        .executable(name: "HL7v2KitCodegen", targets: ["HL7v2KitCodegen"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HL7v2Kit",
            dependencies: ["HL7v2KitDictionaries"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .target(
            name: "HL7v2KitDictionaries",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "HL7v2KitCodegen",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "HL7v2KitTests",
            dependencies: ["HL7v2Kit"],
            resources: [
                .copy("../Fixtures"),
            ]
        ),
        .testTarget(
            name: "HL7v2KitDictionariesTests",
            dependencies: ["HL7v2KitDictionaries"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
