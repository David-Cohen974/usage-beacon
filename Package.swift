// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageBeacon",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "UsageBeaconApp",
            targets: ["UsageBeaconApp"]
        ),
        .executable(
            name: "UsageBeaconWidgetExtension",
            targets: ["UsageBeaconWidget"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.9.6"
        )
    ],
    targets: [
        .target(
            name: "UsageBeaconShared"
        ),
        .executableTarget(
            name: "UsageBeaconApp",
            dependencies: [
                "UsageBeaconShared",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit"),
                .linkedFramework("WidgetKit")
            ]
        ),
        .executableTarget(
            name: "UsageBeaconWidget",
            dependencies: ["UsageBeaconShared"],
            swiftSettings: [
                .unsafeFlags(["-application-extension"])
            ],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("WidgetKit")
            ]
        ),
        .testTarget(
            name: "UsageBeaconAppTests",
            dependencies: ["UsageBeaconApp", "UsageBeaconShared"]
        )
    ]
)
