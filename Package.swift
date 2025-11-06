// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ElgatoCameraControl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ElgatoCameraControl",
            targets: ["ElgatoCameraControl"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ElgatoCameraControl",
            dependencies: [],
            path: "Sources"
        )
    ]
)
