// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KubernetesStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "KubeStatusKit"),
        .executableTarget(
            name: "KubernetesStatus",
            dependencies: ["KubeStatusKit"]
        ),
        .testTarget(
            name: "KubeStatusKitTests",
            dependencies: ["KubeStatusKit"]
        ),
    ]
)
