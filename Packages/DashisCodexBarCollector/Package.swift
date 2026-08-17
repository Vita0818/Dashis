// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DashisCodexBarCollector",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "DashisCollectorContract", targets: ["DashisCollectorContract"]),
        .library(name: "CodexBarCollector", targets: ["CodexBarCollector"]),
    ],
    dependencies: [
        .package(path: "../../Vendor/CodexBarCore"),
    ],
    targets: [
        .target(
            name: "DashisCollectorContract",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .target(
            name: "CodexBarCollector",
            dependencies: [
                "DashisCollectorContract",
                .product(name: "CodexBarCore", package: "CodexBarCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "CodexBarCollectorTests",
            dependencies: [
                "CodexBarCollector",
                "DashisCollectorContract",
                .product(name: "CodexBarCore", package: "CodexBarCore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
    ])
