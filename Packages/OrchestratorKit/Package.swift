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
        .library(name: "OrchestratorKit", targets: ["OrchestratorKit"]),
        /// The Mac app's embedded terminal (SwiftTerm and the panel's terminal WebSocket).
        .library(name: "OrchestratorTerminal", targets: ["OrchestratorTerminal"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.11.2"))
    ],
    targets: [
        .target(
            name: "OrchestratorKit",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "OrchestratorTerminal",
            dependencies: ["OrchestratorKit", .product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "OrchestratorKitTests",
            dependencies: ["OrchestratorKit"],
            swiftSettings: swiftSettings
        )
    ]
)
