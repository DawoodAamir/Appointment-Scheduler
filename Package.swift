// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SchedulerCore", platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "SchedulerCore", targets: ["SchedulerCore"])],
    targets: [
        .target(name: "SchedulerCore", path: "Sources/Core"),
        .testTarget(name: "SchedulerCoreTests", dependencies: ["SchedulerCore"], path: "Tests"),
    ])
