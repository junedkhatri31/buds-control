// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BudsControl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BudsControl", targets: ["BudsControl"]),
        .library(name: "BudsKit", targets: ["BudsKit"]),
    ],
    targets: [
        .target(name: "BudsKit", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .executableTarget(name: "BudsControl", dependencies: ["BudsKit"]),
        .testTarget(name: "BudsKitTests", dependencies: ["BudsKit"]),
    ]
)
