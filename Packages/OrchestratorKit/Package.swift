// swift-tools-version: 6.2
import PackageDescription

/// Settings mirror the app targets: Swift 5 language mode with approachable concurrency,
/// default isolation `nonisolated`, view models annotated `@MainActor` explicitly.
let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v5),
    .enableUpcomingFeature("MemberImportVisibility"),
    // What Xcode's SWIFT_APPROACHABLE_CONCURRENCY = YES turns on.
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault")
]

let package = Package(
    name: "OrchestratorKit",
    platforms: [
        .iOS("26.5"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "OrchestratorKit", targets: ["OrchestratorKit"])
    ],
    targets: [
        .target(
            name: "OrchestratorKit",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "OrchestratorKitTests",
            dependencies: ["OrchestratorKit"],
            swiftSettings: swiftSettings
        )
    ]
)
