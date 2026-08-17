// swift-tools-version: 6.2
import Foundation
import PackageDescription

let sqlite3LibraryDirectory = ProcessInfo.processInfo.environment["CODEXBAR_SQLITE3_LIB_DIR"]?
    .trimmingCharacters(in: .whitespacesAndNewlines)
let sqlite3LinkerSettings: [LinkerSetting] = if let sqlite3LibraryDirectory,
                                                !sqlite3LibraryDirectory.isEmpty
{
    [.unsafeFlags(["-L\(sqlite3LibraryDirectory)"], .when(platforms: [.linux]))]
} else {
    []
}

let package = Package(
    name: "CodexBarCoreSnapshot",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CodexBarCore", targets: ["CodexBarCore"]),
        .executable(name: "CodexBarClaudeWatchdog", targets: ["CodexBarClaudeWatchdog"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
        .package(url: "https://github.com/apple/swift-log", exact: "1.13.2"),
        .package(url: "https://github.com/steipete/SweetCookieKit", exact: "0.4.1"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"]),
            ]),
        .target(
            name: "CodexBarCore",
            dependencies: [
                .target(name: "CSQLite3", condition: .when(platforms: [.linux])),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ],
            linkerSettings: sqlite3LinkerSettings),
        .executableTarget(
            name: "CodexBarClaudeWatchdog",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
    ])
