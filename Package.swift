// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeMachineViewer",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TimeMachineViewer", targets: ["TimeMachineViewer"]),
    ],
    targets: [
        .target(name: "TMCore"),
        .executableTarget(name: "TimeMachineViewer", dependencies: ["TMCore"]),
        .testTarget(name: "TMCoreTests", dependencies: ["TMCore"]),
    ]
)
