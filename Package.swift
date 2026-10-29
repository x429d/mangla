// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mangla",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Mangla", targets: ["Mangla"])
    ],
    targets: [
        .executableTarget(
            name: "Mangla",
            path: "Sources/Mangla",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ManglaTests",
            dependencies: ["Mangla"],
            path: "Tests/ManglaTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
