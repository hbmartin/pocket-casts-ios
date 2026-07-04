// swift-tools-version: 5.10

import PackageDescription
import CompilerPluginSupport
import Foundation

/// Strict-concurrency hardening while staying in the Swift 5 language mode:
/// diagnostics surface as warnings, not errors. Applied target-by-target.
let strictConcurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
]

/// Same as `strictConcurrencySettings` plus -enable-testing, pre-concatenated so the
/// package manifest stays simple enough for the manifest type-checker.
let strictConcurrencyTestableSettings: [SwiftSetting] = strictConcurrencySettings + [
    .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
]

let package = Package(
    name: "Modules",
    platforms: [
        .iOS("18.0"), .macOS(.v10_15)
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
            name: "EndOfYear",
            targets: ["EndOfYear"]
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
        .target(
            name: "EndOfYear",
            dependencies: [
                "PocketCastsDataModel",
                "PocketCastsServer",
                "PocketCastsUtils",
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: "Sources/EndOfYear",
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
                "EndOfYear",
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
    static let podcastsIntents = "PodcastsIntents"
    static let podcastsIntentsUI = "PodcastsIntentsUI"
    static let widgetExtension = "WidgetExtension"
}

enum XcodeSupport {
    static var products: [Product] {
        [
            XcodeTargetNames.podcasts,
            XcodeTargetNames.notificationExtension,
            XcodeTargetNames.podcastsIntents,
            XcodeTargetNames.podcastsIntentsUI,
            XcodeTargetNames.widgetExtension,
        ].map { .supportingProduct(forXcodeTarget: $0) }
    }

    static var targets: [Target] {
        [
            .xcodeTarget(
                XcodeTargetNames.podcasts,
                dependencies: [
                    "PocketCastsDataModel",
                    "PocketCastsServer",
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
                    "EndOfYear",
                ]
            ),
            .xcodeTarget(
                XcodeTargetNames.notificationExtension,
                dependencies: [
                    "PocketCastsServer",
                ]
            ),
            .xcodeTarget(
                XcodeTargetNames.podcastsIntents,
                dependencies: [
                    .product(name: "Fuse", package: "fuse-swift"),
                ]
            ),
            .xcodeTarget(XcodeTargetNames.podcastsIntentsUI, dependencies: []),
            .xcodeTarget(
                XcodeTargetNames.widgetExtension,
                dependencies: [
                    "PocketCastsUtils",
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
