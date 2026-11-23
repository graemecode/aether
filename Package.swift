// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Aether",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AetherCore", targets: ["AetherCore"]),
        .executable(name: "Aether", targets: ["Aether"])
    ],
    targets: [
        .target(
            name: "AetherCore",
            path: "Sources/AetherCore",
            linkerSettings: [
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "Aether",
            dependencies: ["AetherCore"],
            path: "Sources/Aether",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "AetherCoreTests",
            dependencies: ["AetherCore"],
            path: "Tests/AetherCoreTests"
        )
    ]
)
