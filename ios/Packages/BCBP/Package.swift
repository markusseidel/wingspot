// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BCBP",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BCBP", targets: ["BCBP"]),
    ],
    targets: [
        .target(name: "BCBP"),
        .testTarget(name: "BCBPTests", dependencies: ["BCBP"]),
    ]
)
