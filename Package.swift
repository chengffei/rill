// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Joule",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "JouleCore", path: "Sources/JouleCore", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "JouleApp", dependencies: ["JouleCore"], path: "Sources/JouleApp"),
        .testTarget(name: "JouleCoreTests", dependencies: ["JouleCore"], path: "Tests/JouleCoreTests")
    ]
)
