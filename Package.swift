// swift-tools-version: 6.0
// HL7v2Kit — HL7 v2.x parser, builder, and validator for Swift.
// Apache 2.0 licensed. See LICENSE.
import PackageDescription

// The MessageViewer example is SwiftUI, so it exists only where the manifest is read on macOS;
// the Linux CI job never sees it.
#if os(macOS)
let viewerProducts: [Product] = [.executable(name: "MessageViewer", targets: ["MessageViewer"])]
let viewerTargets: [Target] = [
    .executableTarget(
        name: "MessageViewer",
        dependencies: ["HL7v2Kit"],
        path: "Examples/MessageViewer"
    ),
]
let viewerTargetNames: [Target.Dependency] = ["MessageViewer"]
#else
let viewerProducts: [Product] = []
let viewerTargets: [Target] = []
let viewerTargetNames: [Target.Dependency] = []
#endif

let package = Package(
    name: "HL7v2Kit",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .library(name: "HL7v2Kit", targets: ["HL7v2Kit"]),
        .executable(name: "HL7v2KitCodegen", targets: ["HL7v2KitCodegen"]),
        .executable(name: "HL7v2KitAnonymise", targets: ["HL7v2KitAnonymise"]),
        .executable(name: "QuickStart", targets: ["QuickStart"]),
    ] + viewerProducts,
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
        .executableTarget(
            name: "QuickStart",
            dependencies: ["HL7v2Kit"],
            path: "Examples/QuickStart"
        ),
        .testTarget(
            name: "HL7v2KitTests",
            dependencies: ["HL7v2Kit"] + viewerTargetNames,
            resources: [
                .copy("../Fixtures"),
            ]
        ),
    ] + viewerTargets,
    swiftLanguageModes: [.v6]
)
