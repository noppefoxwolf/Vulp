// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MediaLoader",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MediaLoader",
            targets: ["MediaLoader"]
        ),
        .library(
            name: "MediaLoader_SwiftUI",
            targets: ["MediaLoader_SwiftUI"]
        ),
        .library(
            name: "MediaLoader_UIKit",
            targets: ["MediaLoader_UIKit"]
        ),
        .library(
            name: "MediaLoader_AppKit",
            targets: ["MediaLoader_AppKit"]
        ),
        .library(
            name: "MediaLoaderUI",
            targets: ["MediaLoaderUI"]
        ),
    ],
    targets: [
        .target(
            name: "MediaLoader",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "MediaLoader_SwiftUI",
            dependencies: ["MediaLoader"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "MediaLoader_UIKit",
            dependencies: ["MediaLoader"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "MediaLoader_AppKit",
            dependencies: ["MediaLoader"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "MediaLoaderUI",
            dependencies: ["MediaLoader", "MediaLoader_SwiftUI", "MediaLoader_UIKit", "MediaLoader_AppKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "MediaLoaderTests",
            dependencies: ["MediaLoader"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "MediaLoaderUITests",
            dependencies: ["MediaLoader", "MediaLoaderUI"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
