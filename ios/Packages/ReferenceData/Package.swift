// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReferenceData",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ReferenceData", targets: ["ReferenceData"]),
    ],
    dependencies: [
        .package(path: "../WingspotCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.12.0"),
    ],
    targets: [
        .target(name: "ReferenceData", dependencies: [
            "WingspotCore",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "ReferenceDataTests", dependencies: ["ReferenceData"]),
    ]
)
