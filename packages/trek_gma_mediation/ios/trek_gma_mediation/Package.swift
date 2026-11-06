// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "trek_gma_mediation",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "trek-gma-mediation", targets: ["trek_gma_mediation"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        // Flutter rewrites this path to the resolved google_mobile_ads plugin.
        .package(name: "google_mobile_ads", path: "../google_mobile_ads"),
        // The AdMob / Ad Manager adapter; it brings AotterTrekSDK with it.
        .package(url: "https://github.com/aotter/AotterTrekMediation-iOS.git", from: "5.0.1"),
    ],
    targets: [
        .target(
            name: "trek_gma_mediation",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "google-mobile-ads", package: "google_mobile_ads"),
                .product(name: "AotterTrekAdMobMediation", package: "AotterTrekMediation-iOS"),
            ]
        )
    ]
)
