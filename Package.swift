// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PushNotificationToken",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "PushNotificationToken",
            type: .dynamic,
            targets: ["PushNotificationToken"]
        )
    ],
    dependencies: [
        .package(path: "vendor/SwiftGodot")
    ],
    targets: [
        .target(
            name: "PushNotificationToken",
            dependencies: ["SwiftGodot"],
            path: "Sources/PushNotificationToken",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
