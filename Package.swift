// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HeadroomCore"),
        .executableTarget(name: "Headroom", dependencies: ["HeadroomCore"]),
        .executableTarget(name: "HeadroomTests", dependencies: ["HeadroomCore"]),
    ]
)
