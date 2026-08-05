// swift-tools-version: 6.3

import PackageDescription
import CompilerPluginSupport
import Foundation

/// Swift 6 language mode: data-race safety enforced as errors. The upcoming
/// features align package targets with the app's approachable-concurrency setting:
/// nonisolated async functions remain on the caller's actor, and isolated protocol
/// conformances are inferred. Applied target-by-target (the package default stays
/// v5 via `swiftLanguageModes`).
let strictConcurrencySettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// Same as `strictConcurrencySettings` plus -enable-testing, pre-concatenated so the
/// package manifest stays simple enough for the manifest type-checker.
let strictConcurrencyTestableSettings: [SwiftSetting] = strictConcurrencySettings + [
    .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
]

let package = Package(
    name: "Modules",
    platforms: [
        // The macOS floor exists for host-side builds (the macro plugin and the
        // GRDBMacrosTests CI job); v14 satisfies the strictest dependency.
        .iOS("26.0"), .macOS(.v14)
    ],
    products: XcodeSupport.products + [
        .library(
            name: "GRDBMacros",
            targets: ["GRDBMacros"]
        ),
        .library(
            name: "PocketCastsUtils",
            targets: ["PocketCastsUtils"]
        ),
        .library(
            name: "PocketCastsDataModel",
            targets: ["PocketCastsDataModel"]
        ),
        .library(
            name: "PocketCastsDataModelTesting",
            targets: ["PocketCastsDataModelTesting"]
        ),
        .library(
            name: "PocketCastsServer",
            targets: ["PocketCastsServer"]
        ),
        .library(
            name: "PocketCastsFileSync",
            targets: ["PocketCastsFileSync"]
        ),
        .library(
            name: "PocketCastsTranscription",
            targets: ["PocketCastsTranscription"]
        ),
        .library(
            name: "PocketCastsReadAloud",
            targets: ["PocketCastsReadAloud"]
        ),
        .library(
            name: "Modules",
            targets: ["Modules"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "510.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-macro-testing", .upToNextMinor(from: "0.6.0")),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
        // Already resolved transitively by swift-macro-testing; declared explicitly so UI snapshot
        // test targets can depend on the `SnapshotTesting` product directly. The lower bound matches
        // swift-macro-testing's own floor so the two stay on a single resolved version.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.4"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/danielebogo/Swime", revision: "6a507c6480de4603bc5b6f178d4b1855b9c05a8c"),
        .package(url: "https://github.com/ra1028/DifferenceKit", from: "1.2.0"),
        .package(url: "https://github.com/krisk/fuse-swift", from: "1.4.0"),
        .package(url: "https://github.com/shiftyjelly/SwipeCellKit", from: "2.7.6"),
        .package(url: "https://github.com/bitdriftlabs/capture-ios.git", .upToNextMinor(from: "0.23.4")),
        .package(url: "https://github.com/Automattic/Agrume", from: "5.6.12"),
        .package(url: "https://github.com/joeldev/JLRoutes", from: "2.1.1"),
        .package(url: "https://github.com/onevcat/Kingfisher", from: "7.10.2"),
        .package(url: "https://github.com/dagronf/SwiftSubtitles", from: "1.8.3"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
        .package(url: "https://github.com/ksemianov/WrappingHStack", from: "0.2.0"),
        .package(url: "https://github.com/Automattic/pocket-casts-ios-fingerprint", revision: "b696bd9a4a495604532b1b7a484ab140c144eccc"),
        // On-device ASR (WhisperKit) + diarization (SpeakerKit). App-target only —
        // must never become a dependency of PocketCastsTranscription, whose tests
        // run on the macOS host.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
    ],
    targets: XcodeSupport.targets + [
        .target(
            name: "GRDBMacros",
            dependencies: [
                "GRDBMacrosPlugin",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/GRDBMacros",
            swiftSettings: strictConcurrencySettings
        ),
        .macro(
            name: "GRDBMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/GRDBMacrosPlugin",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "GRDBMacrosTests",
            dependencies: [
                "GRDBMacrosPlugin",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ],
            path: "Tests/GRDBMacrosTests",
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "PocketCastsUtils",
            dependencies: [
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Sources/PocketCastsUtils",
            swiftSettings: strictConcurrencyTestableSettings
        ),
        .testTarget(
            name: "PocketCastsUtilsTests",
            dependencies: [
                "PocketCastsUtils",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Tests/PocketCastsUtilsTests",
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "PocketCastsDataModel",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "PocketCastsUtils",
                .product(name: "Dependencies", package: "swift-dependencies"),
                "GRDBMacros",
            ],
            path: "Sources/PocketCastsDataModel",
            swiftSettings: strictConcurrencyTestableSettings
        ),
        .target(
            name: "PocketCastsDataModelTesting",
            dependencies: ["PocketCastsDataModel"],
            path: "Sources/PocketCastsDataModelTesting",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "PocketCastsDataModelTests",
            dependencies: [
                "PocketCastsDataModel",
                "PocketCastsDataModelTesting",
                .product(name: "Dependencies", package: "swift-dependencies"),
            ],
            path: "Tests/PocketCastsDataModelTests",
            resources: [.copy("Fixtures")],
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "PocketCastsServer",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Swime", package: "Swime"),
                "PocketCastsDataModel",
                "PocketCastsUtils",
            ],
            path: "Sources/PocketCastsServer",
            swiftSettings: strictConcurrencyTestableSettings,
            linkerSettings: [
                .linkedFramework("CFNetwork", .when(platforms: [.iOS])),
                .linkedFramework("AuthenticationServices", .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "PocketCastsServerTests",
            dependencies: [
                "PocketCastsDataModel",
                "PocketCastsServer",
            ],
            path: "Tests/PocketCastsServerTests",
            resources: [.copy("Fixtures")],
            swiftSettings: strictConcurrencySettings
        ),
        // Uploads folder backing the Files library: audio files in a
        // user-visible cloud folder (iCloud Drive or any picked Files.app
        // location) appear as user episodes on every device pointing at the
        // same folder.
        .target(
            name: "PocketCastsFileSync",
            dependencies: [
                "PocketCastsDataModel",
                "PocketCastsUtils",
            ],
            path: "Sources/PocketCastsFileSync",
            swiftSettings: strictConcurrencyTestableSettings
        ),
        .testTarget(
            name: "PocketCastsFileSyncTests",
            dependencies: [
                "PocketCastsFileSync",
                "PocketCastsDataModel",
                "PocketCastsDataModelTesting",
            ],
            path: "Tests/PocketCastsFileSyncTests",
            swiftSettings: strictConcurrencySettings
        ),
        // Diarized transcription: domain types, speaker/ASR merge algorithm, VTT
        // serializer, and the Apple SpeechAnalyzer engine (`#if os(iOS)`). System
        // frameworks only, with NO package dependencies: the pure alignment and
        // serialization code is tested host-side (`swift test` on macOS), so
        // nothing that fails to build for macOS (PocketCastsUtils imports UIKit)
        // may be attached here — and WhisperKit/SpeakerKit/FluidAudio products
        // must NOT be added either; they attach only to `XcodeTarget_podcasts`.
        .target(
            name: "PocketCastsTranscription",
            path: "Sources/PocketCastsTranscription",
            swiftSettings: strictConcurrencyTestableSettings
        ),
        .testTarget(
            name: "PocketCastsTranscriptionTests",
            dependencies: [
                "PocketCastsTranscription",
            ],
            path: "Tests/PocketCastsTranscriptionTests",
            swiftSettings: strictConcurrencySettings
        ),
        // Read Aloud: turning a text document into a narrated episode. Holds the
        // pure half — extraction, encoding sniffing, chunking, the synthesis
        // engine protocol — plus the Apple `AVSpeechSynthesizer` engine
        // (`#if os(iOS)`). Same rules as PocketCastsTranscription above: system
        // frameworks only and NO package dependencies, so the chunker and
        // extractors stay testable host-side. Everything stateful (queue,
        // keychain, DB, UI) lives app-side in `podcasts/ReadAloud/`.
        .target(
            name: "PocketCastsReadAloud",
            path: "Sources/PocketCastsReadAloud",
            swiftSettings: strictConcurrencyTestableSettings
        ),
        .testTarget(
            name: "PocketCastsReadAloudTests",
            dependencies: [
                "PocketCastsReadAloud",
            ],
            path: "Tests/PocketCastsReadAloudTests",
            swiftSettings: strictConcurrencySettings
        ),
        .target(
            name: "Modules",
            path: "Sources/Modules",
            swiftSettings: strictConcurrencySettings
        ),
        .testTarget(
            name: "ModulesTests",
            dependencies: ["Modules"],
            path: "Tests/ModulesTests",
            swiftSettings: strictConcurrencySettings
        ),
        // UI snapshot-testing pilot. Image snapshots render through `UIHostingController`, so this
        // target must run on an iOS Simulator (e.g. `make test_staging ONLY_TESTING=SnapshotTests`)
        // rather than via `swift test` on the macOS host. Reference images live in
        // `Tests/SnapshotTests/__Snapshots__` and are excluded so SwiftPM does not treat them as
        // source resources. See `docs/snapshot-testing.md`.
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "PocketCastsDataModel",
                "PocketCastsUtils",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/SnapshotTests",
            exclude: ["__Snapshots__"],
            swiftSettings: strictConcurrencySettings
        )
    ]
)

// MARK: - XcodeSupport (Xcode Targets)

enum XcodeTargetNames {
    static let podcasts = "podcasts"
    static let notificationExtension = "NotificationExtension"
    static let widgetExtension = "WidgetExtension"
    static let pocketCastsTests = "PocketCastsTests"
}

enum XcodeSupport {
    static var products: [Product] {
        [
            XcodeTargetNames.podcasts,
            XcodeTargetNames.notificationExtension,
            XcodeTargetNames.widgetExtension,
            XcodeTargetNames.pocketCastsTests,
        ].map { .supportingProduct(forXcodeTarget: $0) }
    }

    static var targets: [Target] {
        [
            .xcodeTarget(
                XcodeTargetNames.podcasts,
                dependencies: [
                    "PocketCastsDataModel",
                    "PocketCastsServer",
                    "PocketCastsFileSync",
                    "PocketCastsTranscription",
                    "PocketCastsReadAloud",
                    "PocketCastsUtils",
                    .product(name: "Dependencies", package: "swift-dependencies"),
                    .product(name: "DifferenceKit", package: "DifferenceKit"),
                    .product(name: "Fuse", package: "fuse-swift"),
                    .product(name: "SwipeCellKit", package: "SwipeCellKit"),
                    .product(name: "Capture", package: "capture-ios"),
                    .product(name: "Agrume", package: "Agrume"),
                    .product(name: "JLRoutes", package: "JLRoutes"),
                    .product(name: "Kingfisher", package: "Kingfisher"),
                    .product(name: "SwiftSubtitles", package: "SwiftSubtitles"),
                    .product(name: "TelemetryDeck", package: "SwiftSDK"),
                    .product(name: "WrappingHStack", package: "WrappingHStack"),
                    .product(name: "Fingerprint", package: "pocket-casts-ios-fingerprint"),
                    .product(name: "WhisperKit", package: "argmax-oss-swift"),
                    .product(name: "SpeakerKit", package: "argmax-oss-swift"),
                ]
            ),
            .xcodeTarget(
                XcodeTargetNames.notificationExtension,
                dependencies: [
                    "PocketCastsServer",
                ]
            ),
            .xcodeTarget(
                XcodeTargetNames.widgetExtension,
                dependencies: [
                    "PocketCastsUtils",
                ]
            ),
            // The app-test target's themed snapshot coverage (program item H2)
            // renders through swift-snapshot-testing; routing the dependency via
            // this supporting product keeps the Xcode project free of direct
            // package references.
            .xcodeTarget(
                XcodeTargetNames.pocketCastsTests,
                dependencies: [
                    .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                ]
            ),
        ]
    }
}

extension Product {
    static func supportingProduct(forXcodeTarget targetName: String) -> Product {
        .library(
            name: "XcodeTarget_\(targetName)",
            targets: [targetName.supportingName]
        )
    }
}

extension Target {
    static func xcodeTarget(_ name: String, dependencies: [Dependency]) -> Target {
        .target(
            name: name.supportingName,
            dependencies: dependencies,
            path: "Sources/XcodeSupport/\(name.replacingOccurrences(of: " ", with: "-").supportingName)",
            swiftSettings: strictConcurrencySettings
        )
    }
}

extension String {
    var supportingName: String {
        "XcodeTarget_\(self)"
    }

    var asDependency: Target.Dependency {
        .target(name: self.supportingName)
    }
}
