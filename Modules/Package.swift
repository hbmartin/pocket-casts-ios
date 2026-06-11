// swift-tools-version: 5.10

import PackageDescription
import CompilerPluginSupport
import Foundation

let package = Package(
    name: "Modules",
    platforms: [
        .iOS("18.0"), .macOS(.v10_15)
    ],
    products: XcodeSupport.products + [
        .library(
            name: "PocketCastsDependencyInjection",
            targets: ["PocketCastsDependencyInjection"]
        ),
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
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.0.0"),
        .package(url: "https://github.com/danielebogo/Swime", branch: "master"),
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
    ],
    targets: XcodeSupport.targets + [
        .target(
            name: "PocketCastsDependencyInjection",
            path: "Sources/PocketCastsDependencyInjection"
        ),
        .testTarget(
            name: "PocketCastsDependencyInjectionTests",
            dependencies: ["PocketCastsDependencyInjection"],
            path: "Tests/PocketCastsDependencyInjectionTests"
        ),
        .target(
            name: "GRDBMacros",
            dependencies: [
                "GRDBMacrosPlugin",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/GRDBMacros"
        ),
        .macro(
            name: "GRDBMacrosPlugin",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/GRDBMacrosPlugin"
        ),
        .testTarget(
            name: "GRDBMacrosTests",
            dependencies: [
                "GRDBMacrosPlugin",
                .product(name: "MacroTesting", package: "swift-macro-testing"),
            ],
            path: "Tests/GRDBMacrosTests"
        ),
        .target(
            name: "PocketCastsUtils",
            path: "Sources/PocketCastsUtils",
            swiftSettings: [
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
            ]
        ),
        .testTarget(
            name: "PocketCastsUtilsTests",
            dependencies: ["PocketCastsUtils"],
            path: "Tests/PocketCastsUtilsTests"
        ),
        .target(
            name: "PocketCastsDataModel",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "PocketCastsUtils",
                "PocketCastsDependencyInjection",
                "GRDBMacros",
            ],
            path: "Sources/PocketCastsDataModel",
            swiftSettings: [
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PocketCastsDataModelTesting",
            dependencies: ["PocketCastsDataModel"],
            path: "Sources/PocketCastsDataModelTesting"
        ),
        .testTarget(
            name: "PocketCastsDataModelTests",
            dependencies: ["PocketCastsDataModel", "PocketCastsDataModelTesting"],
            path: "Tests/PocketCastsDataModelTests"
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
            swiftSettings: [
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
            ],
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
            resources: [.copy("Fixtures")]
        ),
        .target(
            name: "EndOfYear",
            dependencies: [
                "PocketCastsDataModel",
                "PocketCastsServer",
                "PocketCastsUtils",
                .product(name: "Kingfisher", package: "Kingfisher"),
            ],
            path: "Sources/EndOfYear"
        ),
        .target(
            name: "Modules",
            path: "Sources/Modules"
        ),
        .testTarget(
            name: "ModulesTests",
            dependencies: ["Modules"],
            path: "Tests/ModulesTests"
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
                    "PocketCastsDependencyInjection",
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
            path: "Sources/XcodeSupport/\(name.replacingOccurrences(of: " ", with: "-").supportingName)"
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
