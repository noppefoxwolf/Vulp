// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Vulp",
    platforms: [
        .iOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "Vulp",
            targets: ["Vulp"]
        ),
        .library(
            name: "Vulp_SwiftUI",
            targets: ["Vulp_SwiftUI"]
        ),
        .library(
            name: "Vulp_UIKit",
            targets: ["Vulp_UIKit"]
        ),
        .library(
            name: "Vulp_AppKit",
            targets: ["Vulp_AppKit"]
        ),
        .library(
            name: "VulpUI",
            targets: ["VulpUI"]
        ),
    ],
    targets: [
        .target(
            name: "Vulp",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "Vulp_SwiftUI",
            dependencies: ["Vulp"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "Vulp_UIKit",
            dependencies: ["Vulp"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "Vulp_AppKit",
            dependencies: ["Vulp"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .target(
            name: "VulpUI",
            dependencies: ["Vulp", "Vulp_SwiftUI", "Vulp_UIKit", "Vulp_AppKit"],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "VulpTests",
            dependencies: ["Vulp"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "VulpUITests",
            dependencies: ["Vulp", "VulpUI"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
