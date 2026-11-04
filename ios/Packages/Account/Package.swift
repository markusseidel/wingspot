// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Account",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Account", targets: ["Account"]),
    ],
    dependencies: [
        // Package.resolved isn't tracked, so the version is pinned here.
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.6"),
    ],
    targets: [
        .target(name: "Account", dependencies: [
            .product(name: "Auth", package: "supabase-swift"),
            .product(name: "Supabase", package: "supabase-swift"),
        ]),
        .testTarget(name: "AccountTests", dependencies: ["Account"]),
    ]
)
