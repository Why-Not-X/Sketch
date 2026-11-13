// swift-tools-version: 5.9
// Engine for Touch Whiteboard. Pure Swift: no UIKit or Metal imports, so every
// module builds and tests on macOS with `swift test`.
import PackageDescription

let package = Package(
    name: "Engine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GestureEngine", targets: ["GestureEngine"]),
        .library(name: "InkModel", targets: ["InkModel"]),
        .library(name: "ResponseMapping", targets: ["ResponseMapping"]),
    ],
    targets: [
        .target(name: "GestureEngine"),
        .target(name: "InkModel"),
        .target(name: "ResponseMapping", dependencies: ["GestureEngine"],
                resources: [.process("Resources")]),
        .testTarget(name: "GestureEngineTests", dependencies: ["GestureEngine"]),
        .testTarget(name: "InkModelTests", dependencies: ["InkModel"]),
        .testTarget(name: "ResponseMappingTests", dependencies: ["ResponseMapping"]),
    ]
)
