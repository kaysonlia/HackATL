// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "EchoCore", targets: ["EchoCore"])],
    targets: [
        .target(name: "EchoCore"),
        .testTarget(name: "EchoCoreTests", dependencies: ["EchoCore"]),
    ]
)
