// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Redshot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Redshot",
            path: "Sources/Redshot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("Vision"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
