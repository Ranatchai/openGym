// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenGymCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "OpenGymCore", targets: ["OpenGymCore"]),
        .executable(name: "json-roundtrip", targets: ["json-roundtrip"]),
    ],
    targets: [
        .target(name: "OpenGymCore"),
        .executableTarget(name: "json-roundtrip", dependencies: ["OpenGymCore"]),
        .testTarget(
            name: "OpenGymCoreTests",
            dependencies: ["OpenGymCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
