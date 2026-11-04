// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rill",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", path: "Sources/CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "RillCore", dependencies: ["CSMC"], path: "Sources/RillCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "RillApp", dependencies: ["RillCore"], path: "Sources/RillApp"),
        .testTarget(name: "RillCoreTests", dependencies: ["RillCore"], path: "Tests/RillCoreTests")
    ]
)
