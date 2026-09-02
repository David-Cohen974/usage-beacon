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
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            exact: "12.12.1"
        ),
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
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .copy("Resources/GoogleService-Info.plist")
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
