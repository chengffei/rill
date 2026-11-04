// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Rill",
    // macOS 26 for Liquid Glass (glassEffect, glass button styles).
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CSMC", path: "Sources/CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "RillCore", dependencies: ["CSMC"], path: "Sources/RillCore",
                swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "RillApp", dependencies: ["RillCore"], path: "Sources/RillApp",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "RillCoreTests", dependencies: ["RillCore"], path: "Tests/RillCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
