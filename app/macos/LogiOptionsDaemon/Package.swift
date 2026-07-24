// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogiOptionsDaemon",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LogiOptionsDaemon", targets: ["LogiOptionsDaemon"]),
    ],
    targets: [
        .executableTarget(
            name: "LogiOptionsDaemon",
            path: "Sources/LogiOptionsDaemon",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("UserNotifications"),
            ]
        ),
    ]
)
