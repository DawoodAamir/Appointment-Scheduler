// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "SchedulerCore", products: [.library(name: "SchedulerCore", targets: ["SchedulerCore"])],
    targets: [
        .target(name: "SchedulerCore", path: "Sources/Core"),
        .testTarget(name: "SchedulerCoreTests", dependencies: ["SchedulerCore"], path: "Tests"),
    ])
