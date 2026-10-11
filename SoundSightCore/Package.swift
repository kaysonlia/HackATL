// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SoundSightCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SoundSightCore", targets: ["SoundSightCore"])],
    targets: [
        .target(name: "SoundSightCore", resources: [.process("Resources")]),
        .testTarget(name: "SoundSightCoreTests", dependencies: ["SoundSightCore"], resources: [.copy("Fixtures")]),
    ]
)
