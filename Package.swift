// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFaceGuard", platforms: [.macOS(.v15)],
    products: [.executable(name: "MacFaceGuard", targets: ["MacFaceGuardApp"])],
    targets: [
        .target(name: "MacFaceGuardCore"),
        .executableTarget(name: "MacFaceGuardApp", dependencies: ["MacFaceGuardCore"]),
        .testTarget(name: "MacFaceGuardCoreTests", dependencies: ["MacFaceGuardCore"])
    ]
)
