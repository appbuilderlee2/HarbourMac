// swift-tools-version: 5.7
import PackageDescription
var products: [Product] = [.executable(name: "HarbourWorker", targets: ["HarbourWorker"])]
var targets: [Target] = [
    .target(name: "HarbourCore"),
    .executableTarget(name: "HarbourWorker"),
    .testTarget(name: "HarbourCoreTests", dependencies: ["HarbourCore"], path: "Tests/HarbourCoreTests")
]
#if os(macOS)
products.append(.executable(name: "HarbourMac", targets: ["HarbourMac"]))
targets.append(.executableTarget(name: "HarbourMac", dependencies: ["HarbourCore"], resources: [.copy("Resources")]))
#endif
let package = Package(name: "HarbourMac", platforms: [.macOS(.v12)], products: products, targets: targets)
