// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyHaptic",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyHaptic",
            path: "Sources/KeyHaptic",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
