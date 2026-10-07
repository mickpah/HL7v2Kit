// swift-tools-version: 6.0
// HL7v2Kit — HL7 v2.x parser, builder, and validator for Swift.
// Apache 2.0 licensed. See LICENSE.
import PackageDescription

let package = Package(
    name: "HL7v2Kit",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "HL7v2Kit", targets: ["HL7v2Kit"]),
        .executable(name: "HL7v2KitCodegen", targets: ["HL7v2KitCodegen"]),
        .executable(name: "HL7v2KitAnonymise", targets: ["HL7v2KitAnonymise"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "HL7v2Kit",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .executableTarget(
            name: "HL7v2KitCodegen",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .executableTarget(
            name: "HL7v2KitAnonymise",
            dependencies: ["HL7v2Kit"],
            swiftSettings: [
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
    ],
    swiftLanguageModes: [.v6]
)
