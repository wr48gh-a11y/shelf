// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shelf",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Shelf", targets: ["Shelf"])
    ],
    targets: [
        .executableTarget(
            name: "Shelf",
            path: "Sources/Shelf",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
