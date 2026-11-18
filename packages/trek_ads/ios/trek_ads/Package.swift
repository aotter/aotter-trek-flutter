// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "trek_ads",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "trek-ads", targets: ["trek_ads"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/aotter/AotterTrekSDK-iOS.git", from: "5.0.1"),
    ],
    targets: [
        .target(
            name: "trek_ads",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "AotterTrekSDK", package: "AotterTrekSDK-iOS"),
            ]
        )
    ]
)
