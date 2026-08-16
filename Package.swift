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
        )
    ],
    targets: [
        .executableTarget(
            name: "UsageBeaconApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("EventKit"),
                .linkedFramework("Security"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "UsageBeaconAppTests",
            dependencies: ["UsageBeaconApp"]
        )
    ]
)
